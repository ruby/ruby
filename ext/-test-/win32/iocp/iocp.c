#include <ruby.h>
#include <ruby/io.h>

static void
iocp_free(void *p)
{
    CloseHandle((HANDLE)p);
}

static const rb_data_type_t iocp_type = {
    "Bug::Win32::IOCP",
    {0, iocp_free, 0,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE
iocp_alloc(VALUE klass)
{
    HANDLE port = CreateIoCompletionPort(INVALID_HANDLE_VALUE, NULL, 0, 0);
    if (!port) {
        rb_syserr_fail(rb_w32_map_errno(GetLastError()), "CreateIoCompletionPort");
    }
    return TypedData_Wrap_Struct(klass, &iocp_type, port);
}

static HANDLE
iocp_port(VALUE self)
{
    return (HANDLE)rb_check_typeddata(self, &iocp_type);
}

static VALUE
iocp_associate(VALUE self, VALUE io)
{
    int fd = rb_io_descriptor(io);
    HANDLE h = (HANDLE)rb_w32_get_osfhandle(fd);

    if (!CreateIoCompletionPort(h, iocp_port(self), (ULONG_PTR)fd, 0)) {
        rb_syserr_fail(rb_w32_map_errno(GetLastError()), "CreateIoCompletionPort");
    }
    return io;
}

/* [key, bytes, overlapped address] of a queued packet, or nil on timeout */
static VALUE
iocp_poll(VALUE self, VALUE timeout)
{
    DWORD bytes = 0;
    ULONG_PTR key = 0;
    OVERLAPPED *ol = NULL;

    if (!GetQueuedCompletionStatus(iocp_port(self), &bytes, &key, &ol, NUM2UINT(timeout)) && !ol) {
        DWORD err = GetLastError();
        if (err == WAIT_TIMEOUT) return Qnil;
        rb_syserr_fail(rb_w32_map_errno(err), "GetQueuedCompletionStatus");
    }
    return rb_ary_new_from_args(3, SIZET2NUM((size_t)key), UINT2NUM(bytes), PTR2NUM(ol));
}

void
Init_iocp(void)
{
    VALUE m = rb_define_module_under(rb_define_module("Bug"), "Win32");
    VALUE c = rb_define_class_under(m, "IOCP", rb_cObject);
    rb_define_alloc_func(c, iocp_alloc);
    rb_define_method(c, "associate", iocp_associate, 1);
    rb_define_method(c, "poll", iocp_poll, 1);
}
