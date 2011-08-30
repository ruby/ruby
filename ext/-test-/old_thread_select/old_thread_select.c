/* test case for deprecated C API */
#include "ruby/ruby.h"
#include "ruby/io.h"

static fd_set * array2fdset(fd_set *fds, VALUE ary, int *max)
{
    long i;

    if (NIL_P(ary))
	return NULL;

    FD_ZERO(fds);
    Check_Type(ary, T_ARRAY);
    for (i = 0; i < RARRAY_LEN(ary); i++) {
	VALUE val = RARRAY_PTR(ary)[i];
	int fd;

	Check_Type(val, T_FIXNUM);
	fd = FIX2INT(val);
	if (fd >= *max)
	    *max = fd + 1;
	FD_SET(fd, fds);
    }

    return fds;
}

static VALUE
old_thread_select(VALUE klass, VALUE r, VALUE w, VALUE e, VALUE timeout)
{
    struct timeval tv;
    struct timeval *tvp = NULL;
    fd_set rfds, wfds, efds;
    fd_set *rp, *wp, *ep;
    int rc;
    int max = 0;

    if (!NIL_P(timeout)) {
	tv = rb_time_timeval(timeout);
	tvp = &tv;
    }
    rp = array2fdset(&rfds, r, &max);
    wp = array2fdset(&wfds, w, &max);
    ep = array2fdset(&efds, w, &max);
    rc = rb_thread_select(max, rp, wp, ep, tvp);
    if (rc == -1)
	rb_sys_fail("rb_wait_for_single_fd");
    return INT2NUM(rc);
}

void
Init_old_thread_select(void)
{
    rb_define_singleton_method(rb_cIO, "old_thread_select",
                               old_thread_select, 4);
}
