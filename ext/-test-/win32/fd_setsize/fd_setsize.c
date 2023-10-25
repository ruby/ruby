#undef FD_SETSIZE
/* redefine smaller size then default 64 */
#define FD_SETSIZE 32
#include <ruby.h>

static VALUE
test_select(VALUE self)
{
    int sd = socket(AF_INET, SOCK_DGRAM, 0);
    struct timeval zero;
    fd_set read;
    fd_set write;
    fd_set error;

    zero.tv_sec = 0;
    zero.tv_usec = 0;

    FD_ZERO(&read);
    FD_ZERO(&write);
    FD_ZERO(&error);

    FD_SET(sd, &read);
    FD_SET(sd, &write);
    FD_SET(sd, &error);

    select(sd+1, &read, &write, &error, &zero);

    return Qtrue;
}

static VALUE
test_fdset(VALUE self)
{
    int i;
    fd_set set;

    FD_ZERO(&set);

    for (i = 0; i < FD_SETSIZE * 2; i++) {
        int sd = socket(AF_INET, SOCK_DGRAM, 0);
        FD_SET(sd, &set);
        if (set.fd_count > FD_SETSIZE) {
            return Qfalse;
        }
    }
    return Qtrue;
}

void
Init_fd_setsize(void)
{
    VALUE m = rb_define_module_under(rb_define_module("Bug"), "Win32");
    rb_define_module_function(m, "test_select", test_select, 0);
    rb_define_module_function(m, "test_fdset", test_fdset, 0);
}
