#include "ruby/ruby.h"
#include "ruby/io.h"

static VALUE
wait_for_single_fd(VALUE ign, VALUE fd, VALUE events, VALUE timeout)
{
    struct timeval tv;
    struct timeval *tvp = NULL;
    int rc;

    if (!NIL_P(timeout)) {
	tv = rb_time_timeval(timeout);
	tvp = &tv;
    }

    rc = rb_wait_for_single_fd(NUM2INT(fd), NUM2INT(events), tvp);
    if (rc == -1)
	rb_sys_fail("rb_wait_for_single_fd");
    return INT2NUM(rc);
}

#ifdef HAVE_KQUEUE
/* ensure rb_wait_for_single_fd works on kqueue descriptors */
#include <sys/types.h>
#include <sys/time.h>
#include <sys/event.h>
static VALUE
kqueue_test_wait(VALUE klass)
{
    int kqfd = -1;
    int p[2] = { -1, -1 };
    struct timeval tv = { 0, 0 };
    const struct timespec ts = { 1, 0 };
    struct kevent kev;
    const char *msg;
    VALUE ret = Qfalse;
    int e = 0;
    int n;

    msg = "pipe";
    if (rb_cloexec_pipe(p) < 0) goto err;

    msg = "kqueue";
    kqfd = kqueue();
    if (kqfd < 0) goto err;

    n = rb_wait_for_single_fd(kqfd, RB_WAITFD_IN, &tv);
    if (n != 0) {
        msg = "spurious wakeup";
        errno = 0;
        goto err;
    }

    msg = "write";
    if (write(p[1], "", 1) < 0) goto err;

    EV_SET(&kev, p[0], EVFILT_READ, EV_ADD, 0, 0, 0);

    msg = "kevent";
    n = kevent(kqfd, &kev, 1, &kev, 1, &ts);
    if (n < 0) goto err;
    msg = NULL;
    if (n == 1) {
        n = rb_wait_for_single_fd(kqfd, RB_WAITFD_IN, &tv);
        ret = INT2NUM(n);
    }
    else {
        rb_warn("kevent did not return readiness");
    }
err:
    if (msg) e = errno;
    if (p[0] >= 0) close(p[0]);
    if (p[1] >= 0) close(p[1]);
    if (kqfd >= 0) close(kqfd);
    if (msg) {
        if (e) rb_syserr_fail(e, msg);
        rb_raise(rb_eRuntimeError, "%s", msg);
    }
    return ret;
}
#endif /* HAVE_KQUEUE */

void
Init_wait_for_single_fd(void)
{
    rb_define_const(rb_cObject, "RB_WAITFD_IN", INT2NUM(RB_WAITFD_IN));
    rb_define_const(rb_cObject, "RB_WAITFD_OUT", INT2NUM(RB_WAITFD_OUT));
    rb_define_const(rb_cObject, "RB_WAITFD_PRI", INT2NUM(RB_WAITFD_PRI));
    rb_define_singleton_method(rb_cIO, "wait_for_single_fd",
                               wait_for_single_fd, 3);
#ifdef HAVE_KQUEUE
    rb_define_singleton_method(rb_cIO, "kqueue_test_wait", kqueue_test_wait, 0);
#endif
}
