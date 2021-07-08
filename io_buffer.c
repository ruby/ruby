/**********************************************************************

  io_buffer.c

  Copyright (C) 2021 Samuel Grant Dawson Williams

**********************************************************************/

#include "ruby/io.h"
#include "ruby/io/buffer.h"

#include "internal/string.h"
#include "internal/bits.h"

VALUE rb_cIOBuffer;
size_t RUBY_IO_BUFFER_PAGE_SIZE;

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

static inline void* io_buffer_map_memory(size_t size)
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

static
void io_buffer_map_file(struct rb_io_buffer *data, int descriptor, size_t size, off_t offset, enum rb_io_buffer_flags flags)
{
#if defined(_WIN32)
    HANDLE file = (HANDLE)_get_osfhandle(descriptor);
    if (!file) rb_sys_fail("io_buffer_map_descriptor:_get_osfhandle");

    DWORD protect = PAGE_READONLY, access = FILE_MAP_READ;

    if (flags & RB_IO_BUFFER_IMMUTABLE) {
        data->flags |= RB_IO_BUFFER_IMMUTABLE;
    } else {
        protect = PAGE_READWRITE;
        access = FILE_MAP_WRITE;
    }

    HANDLE mapping = CreateFileMapping(file, NULL, protect, 0, 0, NULL);
    if (!mapping) rb_sys_fail("io_buffer_map_descriptor:CreateFileMapping");

    if (flags & RB_IO_BUFFER_PRIVATE) {
        access |= FILE_MAP_COPY;
        data->flags |= RB_IO_BUFFER_PRIVATE;
    }

    void *base = MapViewOfFile(mapping, access, (DWORD)(offset >> 32), (DWORD)(offset & 0xFFFFFFFF), size);

    if (!base) {
        CloseHandle(mapping);
        rb_sys_fail("io_buffer_map_file:MapViewOfFile");
    }

    data->mapping = mapping;
#else
    int protect = PROT_READ, access = 0;

    if (flags & RB_IO_BUFFER_IMMUTABLE) {
        data->flags |= RB_IO_BUFFER_IMMUTABLE;
    } else {
        protect |= PROT_WRITE;
    }

    if (flags & RB_IO_BUFFER_PRIVATE) {
        data->flags |= RB_IO_BUFFER_PRIVATE;
    } else {
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

static inline void io_buffer_unmap(void* base, size_t size)
{
#ifdef _WIN32
    VirtualFree(base, 0, MEM_RELEASE);
#else
    munmap(base, size);
#endif
}

static void io_buffer_initialize(struct rb_io_buffer *data, void *base, size_t size, enum rb_io_buffer_flags flags, VALUE source)
{
    data->flags = flags;
    data->size = size;

    if (base) {
        data->base = base;
    } else {
        if (data->flags & RB_IO_BUFFER_INTERNAL) {
            data->base = calloc(data->size, 1);
        } else if (data->flags & RB_IO_BUFFER_MAPPED) {
            data->base = io_buffer_map_memory(data->size);
        }
    }

    if (!data->base) {
        rb_raise(rb_eRuntimeError, "Could not allocate buffer!");
    }

    data->source = source;
}

static int io_buffer_free(struct rb_io_buffer *data)
{
    if (data->base) {
        if (data->flags & RB_IO_BUFFER_INTERNAL) {
            free(data->base);
        }

        if (data->flags & RB_IO_BUFFER_MAPPED) {
            io_buffer_unmap(data->base, data->size);
        }

        data->base = NULL;

#if defined(_WIN32)
        if (data->mapping) {
            CloseHandle(data->mapping);
            data->mapping = NULL;
        }
#endif

        return 1;
    }

    return 0;
}

void rb_io_buffer_type_mark(void *_data)
{
    struct rb_io_buffer *data = _data;
    rb_gc_mark(data->source);
}

void rb_io_buffer_type_free(void *_data)
{
    struct rb_io_buffer *data = _data;

    io_buffer_free(data);

    free(data);
}

size_t rb_io_buffer_type_size(const void *_data)
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

VALUE rb_io_buffer_type_allocate(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    VALUE instance = TypedData_Make_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    data->base = NULL;
    data->size = 0;
    data->flags = 0;
    data->source = Qnil;

    return instance;
}

VALUE rb_io_buffer_type_for(VALUE klass, VALUE string)
{
  VALUE instance = rb_io_buffer_type_allocate(klass);

  struct rb_io_buffer *data = NULL;
  TypedData_Get_Struct(instance, struct rb_io_buffer, &rb_io_buffer_type, data);

  io_buffer_initialize(data, RSTRING_PTR(string), RSTRING_LEN(string), 0, string);

  return instance;
}

VALUE rb_io_buffer_new(void *base, size_t size, enum rb_io_buffer_flags flags)
{
    VALUE instance = rb_io_buffer_type_allocate(rb_cIOBuffer);

    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(instance, struct rb_io_buffer, &rb_io_buffer_type, data);

    io_buffer_initialize(data, base, size, 0, Qnil);

    return instance;
}

VALUE rb_io_buffer_map(VALUE io, size_t size, off_t offset, enum rb_io_buffer_flags flags)
{
    VALUE instance = rb_io_buffer_type_allocate(rb_cIOBuffer);

    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(instance, struct rb_io_buffer, &rb_io_buffer_type, data);

    int descriptor = rb_io_descriptor(io);

    io_buffer_map_file(data, descriptor, size, offset, flags);

    return instance;
}

static
VALUE io_buffer_map(int argc, VALUE *argv, VALUE klass)
{
    if (argc < 1 || argc > 4) {
        rb_error_arity(argc, 2, 4);
    }

    VALUE io = argv[0];

    size_t size;
    if (argc >= 2) {
        size = RB_NUM2SIZE(argv[1]);
    } else {
        size = rb_file_size(io);
    }

    off_t offset = 0;
    if (argc >= 3) {
        offset = NUM2OFFT(argv[2]);
    }

    enum rb_io_buffer_flags flags = RB_IO_BUFFER_IMMUTABLE;
    if (argc >= 4) {
        flags = RB_NUM2UINT(argv[3]);
    }

    return rb_io_buffer_map(io, size, offset, flags);
}

VALUE rb_io_buffer_initialize(int argc, VALUE *argv, VALUE self)
{
    if (argc < 1 || argc > 2) {
        rb_error_arity(argc, 1, 2);
    }

    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    size_t size = RB_NUM2SIZE(argv[0]);

    enum rb_io_buffer_flags flags = 0;
    if (argc >= 2) {
        flags = RB_NUM2UINT(argv[1]);
    } else {
        if (size > RUBY_IO_BUFFER_PAGE_SIZE) {
            flags |= RB_IO_BUFFER_MAPPED;
        } else {
            flags |= RB_IO_BUFFER_INTERNAL;
        }
    }

    io_buffer_initialize(data, NULL, size, flags, Qnil);

    return self;
}

static int io_buffer_validate_slice(VALUE source, void *base, size_t size)
{
    const void *source_base = NULL;
    size_t source_size = 0;

    if (RB_TYPE_P(source, T_STRING)) {
        RSTRING_GETMEM(source, source_base, source_size);
    } else {
        rb_io_buffer_get_immutable(source, &source_base, &source_size);
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

static int io_buffer_validate(struct rb_io_buffer *data)
{
    if (data->source != Qnil) {
        // Only slices incur this overhead, unfortunately... better safe than sorry!
        return io_buffer_validate_slice(data->source, data->base, data->size);
    } else {
        return 1;
    }
}

VALUE rb_io_buffer_to_s(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    VALUE result = rb_str_new_cstr("#<");

    rb_str_append(result, rb_class_name(CLASS_OF(self)));
    rb_str_catf(result, " %p+%ld", data->base, data->size);

    if (data->flags & RB_IO_BUFFER_INTERNAL) {
        rb_str_cat2(result, " INTERNAL");
    }

    if (data->flags & RB_IO_BUFFER_MAPPED) {
        rb_str_cat2(result, " MAPPED");
    }

    if (data->flags & RB_IO_BUFFER_LOCKED) {
        rb_str_cat2(result, " LOCKED");
    }

    if (data->flags & RB_IO_BUFFER_IMMUTABLE) {
        rb_str_cat2(result, " IMMUTABLE");
    }

    if (data->source != Qnil) {
        rb_str_cat2(result, " SLICE");
    }

    if (!io_buffer_validate(data)) {
        rb_str_cat2(result, " INVALID");
    }

    return rb_str_cat2(result, ">");

}

static VALUE io_buffer_hexdump(VALUE string, size_t width, char *base, size_t size)
{
    char *text = alloca(width+1);
    text[width] = '\0';

    for (size_t offset = 0; offset < size; offset += width) {
        memset(text, '\0', width);
        rb_str_catf(string, "\n0x%08zx ", offset);

        for (size_t i = 0; i < width; i += 1) {
            if (offset+i < size) {
                unsigned char value = ((unsigned char*)base)[offset+i];

                if (value < 127 && isprint(value)) {
                    text[i] = (char)value;
                } else {
                    text[i] = '.';
                }

                rb_str_catf(string, " %02x", value);
            } else {
                rb_str_cat2(string, "   ");
            }
        }

        rb_str_catf(string, " %s", text);
    }

    rb_str_cat2(string, "\n");

    return string;
}

VALUE rb_io_buffer_inspect(int argc, VALUE *argv, VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    VALUE result = rb_io_buffer_to_s(self);

    if (io_buffer_validate(data)) {
        io_buffer_hexdump(result, 16, data->base, data->size);
    }

    return result;
}

VALUE rb_io_buffer_size(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    return SIZET2NUM(data->size);
}

static VALUE rb_io_buffer_external_p(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    return data->flags & (RB_IO_BUFFER_INTERNAL | RB_IO_BUFFER_MAPPED) ? Qfalse : Qtrue;
}

static VALUE rb_io_buffer_internal_p(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    return data->flags & RB_IO_BUFFER_INTERNAL ? Qtrue : Qfalse;
}

static VALUE rb_io_buffer_mapped_p(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    return data->flags & RB_IO_BUFFER_MAPPED ? Qtrue : Qfalse;
}

static VALUE rb_io_buffer_locked_p(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    return data->flags & RB_IO_BUFFER_LOCKED ? Qtrue : Qfalse;
}

static VALUE rb_io_buffer_immutable_p(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    return data->flags & RB_IO_BUFFER_IMMUTABLE ? Qtrue : Qfalse;
}

VALUE rb_io_buffer_lock(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    if (data->flags & RB_IO_BUFFER_LOCKED) {
        rb_raise(rb_eRuntimeError, "Buffer already locked!");
    }

    data->flags |= RB_IO_BUFFER_LOCKED;

    return self;
}

VALUE rb_io_buffer_unlock(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    if (!(data->flags & RB_IO_BUFFER_LOCKED)) {
        rb_raise(rb_eRuntimeError, "Buffer not locked!");
    }

    data->flags &= ~RB_IO_BUFFER_LOCKED;

    return self;
}

VALUE rb_io_buffer_free(VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    io_buffer_free(data);

    return self;
}

static inline void rb_io_buffer_validate(struct rb_io_buffer *data, size_t offset, size_t length)
{
    if (offset + length > data->size) {
        rb_raise(rb_eRuntimeError, "Specified offset + length exceeds source size!");
    }
}

VALUE rb_io_buffer_slice(VALUE self, VALUE _offset, VALUE _length)
{
    // TODO fail on negative offets/lengths.
    size_t offset = NUM2SIZET(_offset);
    size_t length = NUM2SIZET(_length);

    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    rb_io_buffer_validate(data, offset, length);

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

VALUE rb_io_buffer_to_str(int argc, VALUE *argv, VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    size_t offset = 0;
    size_t length = data->size;

    if (argc == 0) {
        // Defaults.
    } else if (argc == 1) {
        offset = NUM2SIZET(argv[0]);
        length = data->size - offset;
    } else if (argc == 2) {
        offset = NUM2SIZET(argv[0]);
        length = NUM2SIZET(argv[1]);
    } else {
        rb_error_arity(argc, 0, 2);
    }

    rb_io_buffer_validate(data, offset, length);

    return rb_usascii_str_new((char*)data->base + offset, length);
}

void rb_io_buffer_get_mutable(VALUE self, void **base, size_t *size)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    if (data->flags & RB_IO_BUFFER_IMMUTABLE) {
        rb_raise(rb_eRuntimeError, "Buffer is immutable!");
    }

    if (!io_buffer_validate(data)) {
        rb_raise(rb_eRuntimeError, "Buffer has been invalidated!");
    }

    if (data && data->base) {
        *base = data->base;
        *size = data->size;

        return;
    }

    rb_raise(rb_eRuntimeError, "Buffer is not allocated!");
}

void rb_io_buffer_get_immutable(VALUE self, const void **base, size_t *size)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    if (!io_buffer_validate(data)) {
        rb_raise(rb_eRuntimeError, "Buffer has been invalidated!");
    }

    if (data && data->base) {
        *base = data->base;
        *size = data->size;

        return;
    }

    rb_raise(rb_eRuntimeError, "Buffer is not allocated!");
}

void rb_io_buffer_copy(VALUE self, VALUE source, size_t offset)
{
    const void *source_base = NULL;
    size_t source_size = 0;

    if (RB_TYPE_P(source, T_STRING)) {
        RSTRING_GETMEM(source, source_base, source_size);
    } else {
        rb_io_buffer_get_immutable(source, &source_base, &source_size);
    }

    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    rb_io_buffer_validate(data, offset, source_size);

    memcpy((char*)data->base + offset, source_base, source_size);
}

static VALUE io_buffer_copy(VALUE self, VALUE source, VALUE offset)
{
    rb_io_buffer_copy(self, source, NUM2SIZET(offset));

    return self;
}

static int io_buffer_external_p(enum rb_io_buffer_flags flags)
{
    return !(flags & (RB_IO_BUFFER_INTERNAL | RB_IO_BUFFER_MAPPED));
}

void rb_io_buffer_resize(VALUE self, size_t size, size_t preserve)
{
    struct rb_io_buffer *data = NULL, updated;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    if (preserve > data->size) {
        rb_raise(rb_eRuntimeError, "Preservation size bigger than buffer size!");
    }

    if (preserve > size) {
        rb_raise(rb_eRuntimeError, "Preservation size bigger than destination size!");
    }

    if (data->flags & RB_IO_BUFFER_LOCKED) {
        rb_raise(rb_eRuntimeError, "Cannot resize locked buffer!");
    }

    // By virtue of this passing, we don't need to do any further validation on the buffer:
    if (io_buffer_external_p(data->flags)) {
        rb_raise(rb_eRuntimeError, "Cannot resize external buffer!");
    }

    io_buffer_initialize(&updated, NULL, size, data->flags, data->source);

    if (data->base && preserve > 0) {
        memcpy(updated.base, data->base, preserve);
    }

    io_buffer_free(data);
    *data = updated;
}

static
VALUE rb_io_buffer_compare(VALUE self, VALUE other)
{
    const void *ptr1, *ptr2;
    size_t size1, size2;

    rb_io_buffer_get_immutable(self, &ptr1, &size1);
    rb_io_buffer_get_immutable(other, &ptr2, &size2);

    if (size1 < size2) {
        return RB_INT2NUM(-1);
    }

    if (size1 > size2) {
        return RB_INT2NUM(1);
    }

    return RB_INT2NUM(memcmp(ptr1, ptr2, size1));
}

static VALUE io_buffer_resize(VALUE self, VALUE size, VALUE preserve)
{
    rb_io_buffer_resize(self, NUM2SIZET(size), NUM2SIZET(preserve));

    return self;
}

static void io_buffer_validate_type(size_t size, size_t offset) {
    if (offset > size) {
        rb_raise(rb_eRuntimeError, "Type extends beyond end of buffer!");
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

static float ruby_swapf32(float value)
{
    union swapf32 swap = {.value = value};
    swap.integral = ruby_swap32(swap.integral);
    return swap.value;
}

union swapf64 {
    uint64_t integral;
    double value;
};

static double ruby_swapf64(double value)
{
    union swapf64 swap = {.value = value};
    swap.integral = ruby_swap64(swap.integral);
    return swap.value;
}

#define DECLAIR_TYPE(name, type, endian, wrap, unwrap, swap) \
static ID RB_IO_BUFFER_TYPE_##name; \
\
static VALUE io_buffer_read_##name(const void* base, size_t size, size_t *offset) \
{ \
    io_buffer_validate_type(size, *offset + sizeof(type)); \
    type value; \
    memcpy(&value, (char*)base + *offset, sizeof(type)); \
    if (endian != RB_IO_BUFFER_HOST_ENDIAN) value = swap(value); \
    *offset += sizeof(type); \
    return wrap(value); \
} \
\
static void io_buffer_write_##name(const void* base, size_t size, size_t *offset, VALUE _value) \
{ \
    io_buffer_validate_type(size, *offset + sizeof(type)); \
    type value = unwrap(_value); \
    if (endian != RB_IO_BUFFER_HOST_ENDIAN) value = swap(value); \
    memcpy((char*)base + *offset, &value, sizeof(type)); \
    *offset += sizeof(type); \
}

DECLAIR_TYPE(U8, uint8_t, RB_IO_BUFFER_BIG_ENDIAN, RB_UINT2NUM, RB_NUM2UINT, ruby_swap8)
DECLAIR_TYPE(S8, int8_t, RB_IO_BUFFER_BIG_ENDIAN, RB_INT2NUM, RB_NUM2INT, ruby_swap8)

DECLAIR_TYPE(u16, uint16_t, RB_IO_BUFFER_LITTLE_ENDIAN, RB_UINT2NUM, RB_NUM2UINT, ruby_swap16)
DECLAIR_TYPE(U16, uint16_t, RB_IO_BUFFER_BIG_ENDIAN, RB_UINT2NUM, RB_NUM2UINT, ruby_swap16)
DECLAIR_TYPE(s16, int16_t, RB_IO_BUFFER_LITTLE_ENDIAN, RB_INT2NUM, RB_NUM2INT, ruby_swap16)
DECLAIR_TYPE(S16, int16_t, RB_IO_BUFFER_BIG_ENDIAN, RB_INT2NUM, RB_NUM2INT, ruby_swap16)

DECLAIR_TYPE(u32, uint32_t, RB_IO_BUFFER_LITTLE_ENDIAN, RB_UINT2NUM, RB_NUM2UINT, ruby_swap32)
DECLAIR_TYPE(U32, uint32_t, RB_IO_BUFFER_BIG_ENDIAN, RB_UINT2NUM, RB_NUM2UINT, ruby_swap32)
DECLAIR_TYPE(s32, int32_t, RB_IO_BUFFER_LITTLE_ENDIAN, RB_INT2NUM, RB_NUM2INT, ruby_swap32)
DECLAIR_TYPE(S32, int32_t, RB_IO_BUFFER_BIG_ENDIAN, RB_INT2NUM, RB_NUM2INT, ruby_swap32)

DECLAIR_TYPE(u64, uint64_t, RB_IO_BUFFER_LITTLE_ENDIAN, RB_ULONG2NUM, RB_NUM2ULONG, ruby_swap64)
DECLAIR_TYPE(U64, uint64_t, RB_IO_BUFFER_BIG_ENDIAN, RB_ULONG2NUM, RB_NUM2ULONG, ruby_swap64)
DECLAIR_TYPE(s64, int64_t, RB_IO_BUFFER_LITTLE_ENDIAN, RB_LONG2NUM, RB_NUM2LONG, ruby_swap64)
DECLAIR_TYPE(S64, int64_t, RB_IO_BUFFER_BIG_ENDIAN, RB_LONG2NUM, RB_NUM2LONG, ruby_swap64)

DECLAIR_TYPE(f32, float, RB_IO_BUFFER_LITTLE_ENDIAN, DBL2NUM, NUM2DBL, ruby_swapf32)
DECLAIR_TYPE(F32, float, RB_IO_BUFFER_BIG_ENDIAN, DBL2NUM, NUM2DBL, ruby_swapf32)
DECLAIR_TYPE(f64, double, RB_IO_BUFFER_LITTLE_ENDIAN, DBL2NUM, NUM2DBL, ruby_swapf64)
DECLAIR_TYPE(F64, double, RB_IO_BUFFER_BIG_ENDIAN, DBL2NUM, NUM2DBL, ruby_swapf64)
#undef DECLAIR_TYPE

VALUE rb_io_buffer_get(const void* base, size_t size, ID type, size_t offset)
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

static VALUE io_buffer_get(VALUE self, VALUE type, VALUE _offset)
{
    const void *base;
    size_t size;
    size_t offset = NUM2SIZET(_offset);

    rb_io_buffer_get_immutable(self, &base, &size);

    return rb_io_buffer_get(base, size, RB_SYM2ID(type), offset);
}

void rb_io_buffer_set(const void* base, size_t size, ID type, size_t offset, VALUE value)
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

static VALUE io_buffer_set(VALUE self, VALUE type, VALUE _offset, VALUE value)
{
    void *base;
    size_t size;
    size_t offset = NUM2SIZET(_offset);

    rb_io_buffer_get_mutable(self, &base, &size);

    rb_io_buffer_set(base, size, RB_SYM2ID(type), offset, value);

    return SIZET2NUM(offset);
}

void rb_io_buffer_clear(VALUE self, uint8_t value, size_t offset, size_t length)
{
    void *base;
    size_t size;

    rb_io_buffer_get_mutable(self, &base, &size);

    if (offset + length > size) {
        rb_raise(rb_eRuntimeError, "Offset + length out of bounds!");
    }

    memset((char*)base + offset, value, length);
}

static
VALUE io_buffer_clear(int argc, VALUE *argv, VALUE self)
{
    struct rb_io_buffer *data = NULL;
    TypedData_Get_Struct(self, struct rb_io_buffer, &rb_io_buffer_type, data);

    if (argc > 3) {
        rb_error_arity(argc, 0, 3);
    }

    uint8_t value = 0;
    if (argc >= 1) {
        value = NUM2UINT(argv[0]);
    }

    size_t offset = 0;
    if (argc >= 2) {
        offset = NUM2SIZET(argv[1]);
    }

    size_t length = data->size;
    if (argc >= 3) {
        length = NUM2SIZET(argv[2]);
    }

    rb_io_buffer_clear(self, value, offset, length);

    return self;
}

void Init_IO_Buffer()
{
    rb_cIOBuffer = rb_define_class_under(rb_cIO, "Buffer", rb_cObject);

    rb_define_alloc_func(rb_cIOBuffer, rb_io_buffer_type_allocate);
    rb_define_singleton_method(rb_cIOBuffer, "for", rb_io_buffer_type_for, 1);

#ifdef _WIN32
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    RUBY_IO_BUFFER_PAGE_SIZE = info.dwPageSize;
#else /* not WIN32 */
    RUBY_IO_BUFFER_PAGE_SIZE = sysconf(_SC_PAGESIZE);
#endif

    // Efficient sicing of mapped buffers:
    rb_define_const(rb_cIOBuffer, "PAGE_SIZE", SIZET2NUM(RUBY_IO_BUFFER_PAGE_SIZE));

    rb_define_singleton_method(rb_cIOBuffer, "map", io_buffer_map, -1);

    // General use:
    rb_define_method(rb_cIOBuffer, "initialize", rb_io_buffer_initialize, -1);
    rb_define_method(rb_cIOBuffer, "inspect", rb_io_buffer_inspect, -1);
    rb_define_method(rb_cIOBuffer, "to_s", rb_io_buffer_to_s, 0);
    rb_define_method(rb_cIOBuffer, "size", rb_io_buffer_size, 0);

    // Flags:
    rb_define_const(rb_cIOBuffer, "EXTERNAL", RB_INT2NUM(RB_IO_BUFFER_EXTERNAL));
    rb_define_const(rb_cIOBuffer, "INTERNAL", RB_INT2NUM(RB_IO_BUFFER_INTERNAL));
    rb_define_const(rb_cIOBuffer, "MAPPED", RB_INT2NUM(RB_IO_BUFFER_MAPPED));
    rb_define_const(rb_cIOBuffer, "LOCKED", RB_INT2NUM(RB_IO_BUFFER_LOCKED));
    rb_define_const(rb_cIOBuffer, "PRIVATE", RB_INT2NUM(RB_IO_BUFFER_PRIVATE));
    rb_define_const(rb_cIOBuffer, "IMMUTABLE", RB_INT2NUM(RB_IO_BUFFER_IMMUTABLE));

    // Endian:
    rb_define_const(rb_cIOBuffer, "LITTLE_ENDIAN", RB_INT2NUM(RB_IO_BUFFER_LITTLE_ENDIAN));
    rb_define_const(rb_cIOBuffer, "BIG_ENDIAN", RB_INT2NUM(RB_IO_BUFFER_BIG_ENDIAN));
    rb_define_const(rb_cIOBuffer, "HOST_ENDIAN", RB_INT2NUM(RB_IO_BUFFER_HOST_ENDIAN));
    rb_define_const(rb_cIOBuffer, "NETWORK_ENDIAN", RB_INT2NUM(RB_IO_BUFFER_NETWORK_ENDIAN));

    rb_define_method(rb_cIOBuffer, "external?", rb_io_buffer_external_p, 0);
    rb_define_method(rb_cIOBuffer, "internal?", rb_io_buffer_internal_p, 0);
    rb_define_method(rb_cIOBuffer, "mapped?", rb_io_buffer_mapped_p, 0);
    rb_define_method(rb_cIOBuffer, "locked?", rb_io_buffer_locked_p, 0);
    rb_define_method(rb_cIOBuffer, "immutable?", rb_io_buffer_immutable_p, 0);

    // Locking to prevent changes while using pointer:
    rb_define_method(rb_cIOBuffer, "lock", rb_io_buffer_lock, 0);
    rb_define_method(rb_cIOBuffer, "unlock", rb_io_buffer_unlock, 0);

    // Manipulation:
    rb_define_method(rb_cIOBuffer, "slice", rb_io_buffer_slice, 2);
    rb_define_method(rb_cIOBuffer, "to_str", rb_io_buffer_to_str, -1);
    rb_define_method(rb_cIOBuffer, "copy", io_buffer_copy, 2);
    rb_define_method(rb_cIOBuffer, "<=>", rb_io_buffer_compare, 1);
    rb_define_method(rb_cIOBuffer, "resize", io_buffer_resize, 2);
    rb_define_method(rb_cIOBuffer, "clear", io_buffer_clear, -1);

    rb_include_module(rb_cIOBuffer, rb_mComparable);

#define DEFINE_TYPE(name) RB_IO_BUFFER_TYPE_##name = rb_intern_const(#name)
    DEFINE_TYPE(U8); DEFINE_TYPE(S8);
    DEFINE_TYPE(u16); DEFINE_TYPE(U16); DEFINE_TYPE(s16); DEFINE_TYPE(S16);
    DEFINE_TYPE(u32); DEFINE_TYPE(U32); DEFINE_TYPE(s32); DEFINE_TYPE(S32);
    DEFINE_TYPE(u64); DEFINE_TYPE(U64); DEFINE_TYPE(s64); DEFINE_TYPE(S64);
    DEFINE_TYPE(f32); DEFINE_TYPE(F32); DEFINE_TYPE(f64); DEFINE_TYPE(F64);
#undef DEFINE_TYPE

    // Data access:
    rb_define_method(rb_cIOBuffer, "get", io_buffer_get, 2);
    rb_define_method(rb_cIOBuffer, "set", io_buffer_set, 3);
}
