/************************************************

  ipsocket.c -

  created at: Thu Mar 31 12:21:29 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

************************************************/

#include "rubysocket.h"
#include <stdio.h>

struct inetsock_arg
{
    VALUE self;
    VALUE io;

    struct {
        VALUE host, serv;
        struct rb_addrinfo *res;
    } remote, local;
    int type;
    VALUE resolv_timeout;
    VALUE connect_timeout;
    VALUE open_timeout;
};

void
rsock_raise_user_specified_timeout(void)
{
    VALUE errno_module = rb_const_get(rb_cObject, rb_intern("Errno"));
    VALUE etimedout_error = rb_const_get(errno_module, rb_intern("ETIMEDOUT"));
    rb_raise(etimedout_error, "user specified timeout");
}

static VALUE
inetsock_cleanup(VALUE v)
{
    struct inetsock_arg *arg = (void *)v;
    if (arg->remote.res) {
        rb_freeaddrinfo(arg->remote.res);
        arg->remote.res = 0;
    }
    if (arg->local.res) {
        rb_freeaddrinfo(arg->local.res);
        arg->local.res = 0;
    }
    if (arg->io != Qnil) {
        rb_io_close(arg->io);
        arg->io = Qnil;
    }
    return Qnil;
}

static VALUE
current_clocktime(void)
{
    VALUE clock_monotnic_const = rb_const_get(rb_mProcess, rb_intern("CLOCK_MONOTONIC"));
    return rb_funcall(rb_mProcess, rb_intern("clock_gettime"), 1, clock_monotnic_const);
}

static VALUE
init_inetsock_internal(VALUE v)
{
    struct inetsock_arg *arg = (void *)v;
    int error = 0;
    int type = arg->type;
    struct addrinfo *res, *lres;
    int status = 0, local = 0;
    int family = AF_UNSPEC;
    const char *syscall = 0;
    VALUE resolv_timeout = arg->resolv_timeout;
    VALUE connect_timeout = arg->connect_timeout;
    VALUE open_timeout = arg->open_timeout;
    VALUE timeout;
    VALUE starts_at;
    unsigned int timeout_msec;

    timeout = NIL_P(open_timeout) ? resolv_timeout : open_timeout;
    timeout_msec = NIL_P(timeout) ? 0 : rsock_value_timeout_to_msec(timeout);
    starts_at = current_clocktime();

    arg->remote.res = rsock_addrinfo(arg->remote.host, arg->remote.serv,
                                     family, SOCK_STREAM,
                                     (type == INET_SERVER) ? AI_PASSIVE : 0, timeout_msec);

    /*
     * Maybe also accept a local address
     */

    if (type != INET_SERVER && (!NIL_P(arg->local.host) || !NIL_P(arg->local.serv))) {
        arg->local.res = rsock_addrinfo(arg->local.host, arg->local.serv,
                                        family, SOCK_STREAM, 0, 0);
    }

    VALUE io = Qnil;

    for (res = arg->remote.res->ai; res; res = res->ai_next) {
#if !defined(INET6) && defined(AF_INET6)
        if (res->ai_family == AF_INET6)
            continue;
#endif
        lres = NULL;
        if (arg->local.res) {
            for (lres = arg->local.res->ai; lres; lres = lres->ai_next) {
                if (lres->ai_family == res->ai_family)
                    break;
            }
            if (!lres) {
                if (res->ai_next || status < 0)
                    continue;
                /* Use a different family local address if no choice, this
                 * will cause EAFNOSUPPORT. */
                lres = arg->local.res->ai;
            }
        }
        status = rsock_socket(res->ai_family,res->ai_socktype,res->ai_protocol);
        syscall = "socket(2)";
        if (status < 0) {
            error = errno;
            continue;
        }

        int fd = status;
        io = arg->io = rsock_init_sock(arg->self, fd);

        if (type == INET_SERVER) {
#if !defined(_WIN32) && !defined(__CYGWIN__)
            status = 1;
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR,
                       (char*)&status, (socklen_t)sizeof(status));
#endif
            status = bind(fd, res->ai_addr, res->ai_addrlen);
            syscall = "bind(2)";
        }
        else {
            if (lres) {
#if !defined(_WIN32) && !defined(__CYGWIN__)
                status = 1;
                setsockopt(fd, SOL_SOCKET, SO_REUSEADDR,
                           (char*)&status, (socklen_t)sizeof(status));
#endif
                status = bind(fd, lres->ai_addr, lres->ai_addrlen);
                local = status;
                syscall = "bind(2)";
            }

            if (NIL_P(open_timeout)) {
                timeout = connect_timeout;
            } else {
                VALUE elapsed = rb_funcall(current_clocktime(), '-', 1, starts_at);
                timeout = rb_funcall(open_timeout, '-', 1, elapsed);
                if (rb_funcall(timeout, '<', 1, INT2FIX(0)) == Qtrue) rsock_raise_user_specified_timeout();
            }

            if (status >= 0) {
                status = rsock_connect(io, res->ai_addr, res->ai_addrlen, (type == INET_SOCKS), timeout);
                syscall = "connect(2)";
            }
        }

        if (status < 0) {
            error = errno;
            arg->io = Qnil;
            rb_io_close(io);
            io = Qnil;
            continue;
        } else {
            break;
        }
    }

    if (status < 0) {
        VALUE host, port;

        if (local < 0) {
            host = arg->local.host;
            port = arg->local.serv;
        } else {
            host = arg->remote.host;
            port = arg->remote.serv;
        }

        rsock_syserr_fail_host_port(error, syscall, host, port);
    }

    // Don't close the socket in `inetsock_cleanup` if we are returning it:
    arg->io = Qnil;

    if (type == INET_SERVER && io != Qnil) {
        status = listen(rb_io_descriptor(io), SOMAXCONN);
        if (status < 0) {
            error = errno;
            rb_io_close(io);
            rb_syserr_fail(error, "listen(2)");
        }
    }

    /* create new instance */
    return io;
}

#if FAST_FALLBACK_INIT_INETSOCK_IMPL == 0

VALUE
rsock_init_inetsock(
    VALUE self, VALUE remote_host, VALUE remote_serv,
    VALUE local_host, VALUE local_serv, int type,
    VALUE resolv_timeout, VALUE connect_timeout, VALUE open_timeout,
    VALUE _fast_fallback, VALUE _test_mode_settings
) {
    if (!NIL_P(open_timeout) && (!NIL_P(resolv_timeout) || !NIL_P(connect_timeout))) {
        rb_raise(rb_eArgError, "Cannot specify open_timeout along with connect_timeout or resolv_timeout");
    }

    struct inetsock_arg arg;
    arg.self = self;
    arg.io = Qnil;
    arg.remote.host = remote_host;
    arg.remote.serv = remote_serv;
    arg.remote.res = 0;
    arg.local.host = local_host;
    arg.local.serv = local_serv;
    arg.local.res = 0;
    arg.type = type;
    arg.resolv_timeout = resolv_timeout;
    arg.connect_timeout = connect_timeout;
    arg.open_timeout = open_timeout;
    return rb_ensure(init_inetsock_internal, (VALUE)&arg,
                     inetsock_cleanup, (VALUE)&arg);
}

#elif FAST_FALLBACK_INIT_INETSOCK_IMPL == 1

#define IPV6_ENTRY_POS 0
#define IPV4_ENTRY_POS 1
#define RESOLUTION_ERROR 0
#define SYSCALL_ERROR 1

static int
is_specified_ip_address(const char *hostname)
{
    if (!hostname) return false;

    struct in_addr ipv4addr;
    struct in6_addr ipv6addr;

    return (inet_pton(AF_INET6, hostname, &ipv6addr) == 1 ||
            inet_pton(AF_INET, hostname, &ipv4addr) == 1);
}

struct fast_fallback_inetsock_arg
{
    VALUE self;
    VALUE io;

    struct {
        VALUE host, serv;
        struct rb_addrinfo *res;
    } remote, local;
    int type;
    VALUE resolv_timeout;
    VALUE connect_timeout;
    VALUE open_timeout;

    const char *hostp, *portp;
    int *families;
    int family_size;
    int additional_flags;
    struct fast_fallback_getaddrinfo_entry *getaddrinfo_entries[2];
    struct fast_fallback_getaddrinfo_shared *getaddrinfo_shared;
    rb_fdset_t readfds, writefds;
    int wait;
    int connection_attempt_fds_size;
    int *connection_attempt_fds;
    VALUE test_mode_settings;
};

static struct fast_fallback_getaddrinfo_shared *
allocate_fast_fallback_getaddrinfo_shared(int family_size)
{
    struct fast_fallback_getaddrinfo_shared *shared;

    shared = (struct fast_fallback_getaddrinfo_shared *)calloc(
        1,
        sizeof(struct fast_fallback_getaddrinfo_shared) + (family_size == 1 ? 0 : 2) * sizeof(struct fast_fallback_getaddrinfo_entry)
    );

    return shared;
}

static void
allocate_fast_fallback_getaddrinfo_hints(struct addrinfo *hints, int family, int remote_addrinfo_hints, int additional_flags)
{
    MEMZERO(hints, struct addrinfo, 1);
    hints->ai_family = family;
    hints->ai_socktype = SOCK_STREAM;
    hints->ai_protocol = IPPROTO_TCP;
    hints->ai_flags = remote_addrinfo_hints;
    hints->ai_flags |= additional_flags;
}

static int*
allocate_connection_attempt_fds(int additional_capacity)
{
    int *fds = (int *)malloc(additional_capacity * sizeof(int));
    if (!fds) rb_syserr_fail(errno, "malloc(3)");
    for (int i = 0; i < additional_capacity; i++) fds[i] = -1;
    return fds;
}

static int
reallocate_connection_attempt_fds(int **fds, int current_capacity, int additional_capacity)
{
    int new_capacity = current_capacity + additional_capacity;
    int *new_fds;

    new_fds = realloc(*fds, new_capacity * sizeof(int));
    if (new_fds == NULL) {
        rb_syserr_fail(errno, "realloc(3)");
    }
    *fds = new_fds;

    for (int i = current_capacity; i < new_capacity; i++) (*fds)[i] = -1;
    return new_capacity;
}

struct hostname_resolution_result
{
    struct addrinfo *ai;
    int finished;
    int has_error;
};

struct hostname_resolution_store
{
    struct hostname_resolution_result v6;
    struct hostname_resolution_result v4;
    int is_all_finished;
};

static int
any_addrinfos(struct hostname_resolution_store *resolution_store)
{
    return resolution_store->v6.ai || resolution_store->v4.ai;
}

static struct timespec
current_clocktime_ts(void)
{
    struct timespec ts;
    if ((clock_gettime(CLOCK_MONOTONIC, &ts)) < 0) {
        rb_syserr_fail(errno, "clock_gettime(2)");
    }
    return ts;
}

static void
set_timeout_tv(struct timeval *tv, long ms, struct timespec from)
{
    long sec = ms / 1000;
    long nsec = (ms % 1000) * 1000000;
    long result_sec = from.tv_sec + sec;
    long result_nsec = from.tv_nsec + nsec;

    result_sec += result_nsec / 1000000000;
    result_nsec = result_nsec % 1000000000;

    tv->tv_sec = result_sec;
    tv->tv_usec = (int)(result_nsec / 1000);
}

static struct timeval
add_ts_to_tv(struct timeval tv, struct timespec ts)
{
    long ts_usec = ts.tv_nsec / 1000;
    tv.tv_sec += ts.tv_sec;
    tv.tv_usec += ts_usec;

    if (tv.tv_usec >= 1000000) {
        tv.tv_sec += tv.tv_usec / 1000000;
        tv.tv_usec = tv.tv_usec % 1000000;
    }

    return tv;
}

static VALUE
tv_to_seconds(struct timeval *timeout) {
    if (timeout == NULL) return Qnil;

    double seconds = (double)timeout->tv_sec + (double)timeout->tv_usec / 1000000.0;

    return DBL2NUM(seconds);
}

static int
is_infinity(struct timeval tv)
{
    // { -1, -1 } as infinity
    return tv.tv_sec == -1 || tv.tv_usec == -1;
}

static int
is_timeout_tv(struct timeval *timeout_tv, struct timespec now) {
    if (!timeout_tv) return false;
    if (timeout_tv->tv_sec == -1 && timeout_tv->tv_usec == -1) return false;

    struct timespec ts;
    ts.tv_sec = timeout_tv->tv_sec;
    ts.tv_nsec = timeout_tv->tv_usec * 1000;

    if (now.tv_sec > ts.tv_sec) return true;
    if (now.tv_sec == ts.tv_sec && now.tv_nsec >= ts.tv_nsec) return true;
    return false;
}

static struct timeval *
select_expires_at(
    struct hostname_resolution_store *resolution_store,
    struct timeval *resolution_delay,
    struct timeval *connection_attempt_delay,
    struct timeval *user_specified_resolv_timeout_at,
    struct timeval *user_specified_connect_timeout_at,
    struct timeval *user_specified_open_timeout_at
) {
    if (any_addrinfos(resolution_store)) {
        struct timeval *delay;
        delay = resolution_delay ? resolution_delay : connection_attempt_delay;

        if (user_specified_open_timeout_at &&
            timercmp(user_specified_open_timeout_at, delay, <)) {
            return user_specified_open_timeout_at;
        }
        return delay;
    }

    if (user_specified_open_timeout_at) return user_specified_open_timeout_at;

    struct timeval *timeout = NULL;

    if (user_specified_resolv_timeout_at) {
        if (is_infinity(*user_specified_resolv_timeout_at)) return NULL;
        timeout = user_specified_resolv_timeout_at;
    }

    if (user_specified_connect_timeout_at) {
        if (is_infinity(*user_specified_connect_timeout_at)) return NULL;
        if (!timeout || timercmp(user_specified_connect_timeout_at, timeout, >)) {
            return user_specified_connect_timeout_at;
        }
    }

    return timeout;
}

static struct timeval
tv_to_timeout(struct timeval *ends_at, struct timespec now)
{
    struct timeval delay;
    struct timespec expires_at;
    expires_at.tv_sec = ends_at->tv_sec;
    expires_at.tv_nsec = ends_at->tv_usec * 1000;

    struct timespec diff;
    diff.tv_sec = expires_at.tv_sec - now.tv_sec;

    if (expires_at.tv_nsec >= now.tv_nsec) {
        diff.tv_nsec = expires_at.tv_nsec - now.tv_nsec;
    } else {
        diff.tv_sec -= 1;
        diff.tv_nsec = (1000000000 + expires_at.tv_nsec) - now.tv_nsec;
    }

    delay.tv_sec = diff.tv_sec;
    delay.tv_usec = (int)diff.tv_nsec / 1000;

    return delay;
}

static struct addrinfo *
pick_addrinfo(struct hostname_resolution_store *resolution_store, int last_family)
{
    int priority_on_v6[2] = { AF_INET6, AF_INET };
    int priority_on_v4[2] = { AF_INET, AF_INET6 };
    int *precedences = last_family == AF_INET6 ? priority_on_v4 : priority_on_v6;
    struct addrinfo *selected_ai = NULL;

    for (int i = 0; i < 2; i++) {
        if (precedences[i] == AF_INET6) {
            selected_ai = resolution_store->v6.ai;
            if (selected_ai) {
                resolution_store->v6.ai = selected_ai->ai_next;
                break;
            }
        } else {
            selected_ai = resolution_store->v4.ai;
            if (selected_ai) {
                resolution_store->v4.ai = selected_ai->ai_next;
                break;
            }
        }
    }
    return selected_ai;
}

static void
socket_nonblock_set(int fd)
{
    int flags = fcntl(fd, F_GETFL);

    if (flags < 0) rb_syserr_fail(errno, "fcntl(2)");
    if ((flags & O_NONBLOCK) != 0) return;

    flags |= O_NONBLOCK;

    if (fcntl(fd, F_SETFL, flags) < 0) rb_syserr_fail(errno, "fcntl(2)");
    return;
}

static int
in_progress_fds(int fds_size)
{
    return fds_size > 0;
}

static void
remove_connection_attempt_fd(int *fds, int *fds_size, int removing_fd) {
    int i, j;

    for (i = 0; i < *fds_size; i++) {
        if (fds[i] != removing_fd) continue;

        for (j = i; j < *fds_size - 1; j++) {
            fds[j] = fds[j + 1];
        }

        (*fds_size)--;
        fds[*fds_size] = -1;
        break;
    }
}

struct fast_fallback_error
{
    int type;
    int ecode;
};

static VALUE
init_fast_fallback_inetsock_internal(VALUE v)
{
    struct fast_fallback_inetsock_arg *arg = (void *)v;
    VALUE io = arg->io;
    VALUE resolv_timeout = arg->resolv_timeout;
    VALUE connect_timeout = arg->connect_timeout;
    VALUE open_timeout = arg->open_timeout;
    VALUE test_mode_settings = arg->test_mode_settings;
    struct addrinfo *remote_ai = NULL, *local_ai = NULL;
    int connected_fd = -1, status = 0, local_status = 0;
    int remote_addrinfo_hints = 0;
    struct fast_fallback_error last_error = { 0, 0 };
    const char *syscall = 0;
    VALUE host, serv;

    #ifdef HAVE_CONST_AI_ADDRCONFIG
    remote_addrinfo_hints |= AI_ADDRCONFIG;
    #endif

    pthread_t threads[arg->family_size];
    char resolved_type[2];
    ssize_t resolved_type_size;
    int hostname_resolution_waiter = -1, hostname_resolution_notifier = -1;
    int pipefd[2];

    int nfds = 0;
    struct timeval *ends_at = NULL;
    struct timeval delay = (struct timeval){ -1, -1 };
    struct timeval *delay_p = NULL;

    struct hostname_resolution_store resolution_store;
    resolution_store.is_all_finished = false;
    resolution_store.v6.ai = NULL;
    resolution_store.v6.finished = false;
    resolution_store.v6.has_error = false;
    resolution_store.v4.ai = NULL;
    resolution_store.v4.finished = false;
    resolution_store.v4.has_error = false;

    int last_family = 0;
    int additional_capacity = 10;
    int current_capacity = additional_capacity;
    arg->connection_attempt_fds = allocate_connection_attempt_fds(additional_capacity);
    arg->connection_attempt_fds_size = 0;

    struct timeval resolution_delay_storage;
    struct timeval *resolution_delay_expires_at = NULL;
    struct timeval connection_attempt_delay_strage;
    struct timeval *connection_attempt_delay_expires_at = NULL;
    struct timeval user_specified_resolv_timeout_storage;
    struct timeval *user_specified_resolv_timeout_at = NULL;
    struct timeval user_specified_connect_timeout_storage;
    struct timeval *user_specified_connect_timeout_at = NULL;
    struct timeval user_specified_open_timeout_storage;
    struct timeval *user_specified_open_timeout_at = NULL;
    struct timespec now = current_clocktime_ts();

    if (!NIL_P(open_timeout)) {
        struct timeval open_timeout_tv = rb_time_interval(open_timeout);
        user_specified_open_timeout_storage = add_ts_to_tv(open_timeout_tv, now);
        user_specified_open_timeout_at = &user_specified_open_timeout_storage;
    }

    /* start of hostname resolution */
    if (arg->family_size == 1) {
        arg->wait = -1;
        arg->getaddrinfo_shared = NULL;

        int family = arg->families[0];
        unsigned int t = NIL_P(resolv_timeout) ? 0 : rsock_value_timeout_to_msec(resolv_timeout);

        arg->remote.res = rsock_addrinfo(
            arg->remote.host,
            arg->remote.serv,
            family,
            SOCK_STREAM,
            0,
            t
        );

        if (family == AF_INET6) {
            resolution_store.v6.ai = arg->remote.res->ai;
            resolution_store.v6.finished = true;
            resolution_store.v4.finished = true;
        } else if (family == AF_INET) {
            resolution_store.v4.ai = arg->remote.res->ai;
            resolution_store.v4.finished = true;
            resolution_store.v6.finished = true;
        }
        resolution_store.is_all_finished = true;
    } else {
        if (pipe(pipefd) != 0) rb_syserr_fail(errno, "pipe(2)");
        hostname_resolution_waiter = pipefd[0];
        int waiter_flags = fcntl(hostname_resolution_waiter, F_GETFL, 0);
        if (waiter_flags < 0) rb_syserr_fail(errno, "fcntl(2)");
        if ((fcntl(hostname_resolution_waiter, F_SETFL, waiter_flags | O_NONBLOCK)) < 0) {
            rb_syserr_fail(errno, "fcntl(2)");
        }
        arg->wait = hostname_resolution_waiter;
        hostname_resolution_notifier = pipefd[1];

        arg->getaddrinfo_shared = allocate_fast_fallback_getaddrinfo_shared(arg->family_size);
        if (!arg->getaddrinfo_shared) rb_syserr_fail(errno, "calloc(3)");

        rb_nativethread_lock_initialize(&arg->getaddrinfo_shared->lock);
        arg->getaddrinfo_shared->notify = hostname_resolution_notifier;

        arg->getaddrinfo_shared->node = arg->hostp ? ruby_strdup(arg->hostp) : NULL;
        arg->getaddrinfo_shared->service = arg->portp ? ruby_strdup(arg->portp) : NULL;
        arg->getaddrinfo_shared->refcount = arg->family_size + 1;

        for (int i = 0; i < arg->family_size; i++) {
            arg->getaddrinfo_entries[i] = &arg->getaddrinfo_shared->getaddrinfo_entries[i];
            arg->getaddrinfo_entries[i]->shared = arg->getaddrinfo_shared;

            struct addrinfo getaddrinfo_hints[arg->family_size];

            allocate_fast_fallback_getaddrinfo_hints(
                &getaddrinfo_hints[i],
                arg->families[i],
                remote_addrinfo_hints,
                arg->additional_flags
            );

            arg->getaddrinfo_entries[i]->hints = getaddrinfo_hints[i];
            arg->getaddrinfo_entries[i]->ai = NULL;
            arg->getaddrinfo_entries[i]->family = arg->families[i];
            arg->getaddrinfo_entries[i]->refcount = 2;
            arg->getaddrinfo_entries[i]->has_syserr = false;
            arg->getaddrinfo_entries[i]->test_sleep_ms = 0;
            arg->getaddrinfo_entries[i]->test_ecode = 0;

            /* for testing HEv2 */
            if (!NIL_P(test_mode_settings) && RB_TYPE_P(test_mode_settings, T_HASH)) {
                const char *family_sym = arg->families[i] == AF_INET6 ? "ipv6" : "ipv4";

                VALUE test_delay_setting = rb_hash_aref(test_mode_settings, ID2SYM(rb_intern("delay")));
                if (!NIL_P(test_delay_setting)) {
                    VALUE rb_test_delay_ms = rb_hash_aref(test_delay_setting, ID2SYM(rb_intern(family_sym)));
                    long test_delay_ms = NIL_P(rb_test_delay_ms) ? 0 : rb_test_delay_ms;
                    arg->getaddrinfo_entries[i]->test_sleep_ms = test_delay_ms;
                }

                VALUE test_error_setting = rb_hash_aref(test_mode_settings, ID2SYM(rb_intern("error")));
                if (!NIL_P(test_error_setting)) {
                    VALUE rb_test_ecode = rb_hash_aref(test_error_setting, ID2SYM(rb_intern(family_sym)));
                    if (!NIL_P(rb_test_ecode)) {
                        arg->getaddrinfo_entries[i]->test_ecode = NUM2INT(rb_test_ecode);
                    }
                }
            }

            if (raddrinfo_pthread_create(&threads[i], fork_safe_do_fast_fallback_getaddrinfo, arg->getaddrinfo_entries[i]) != 0) {
                rsock_raise_resolution_error("getaddrinfo(3)", EAI_AGAIN);
            }
            pthread_detach(threads[i]);
        }

        if (NIL_P(resolv_timeout)) {
            user_specified_resolv_timeout_storage = (struct timeval){ -1, -1 };
        } else {
            struct timeval resolv_timeout_tv = rb_time_interval(resolv_timeout);
            user_specified_resolv_timeout_storage = add_ts_to_tv(resolv_timeout_tv, now);
        }
        user_specified_resolv_timeout_at = &user_specified_resolv_timeout_storage;
    }

    while (true) {
        /* start of connection */
        if (any_addrinfos(&resolution_store) &&
            !resolution_delay_expires_at &&
            !connection_attempt_delay_expires_at) {
            while ((remote_ai = pick_addrinfo(&resolution_store, last_family))) {
                int fd = -1;

                #if !defined(INET6) && defined(AF_INET6)
                if (remote_ai->ai_family == AF_INET6) {
                    if (any_addrinfos(&resolution_store)) continue;
                    if (!in_progress_fds(arg->connection_attempt_fds_size)) break;
                    if (resolution_store.is_all_finished) break;

                    if (local_status < 0) {
                        host = arg->local.host;
                        serv = arg->local.serv;
                    } else {
                        host = arg->remote.host;
                        serv = arg->remote.serv;
                    }
                    if (last_error.type == RESOLUTION_ERROR) {
                        rsock_raise_resolution_error(syscall, last_error.ecode);
                    } else {
                        rsock_syserr_fail_host_port(last_error.ecode, syscall, host, serv);
                    }
                }
                #endif

                local_ai = NULL;

                if (arg->local.res) {
                    for (local_ai = arg->local.res->ai; local_ai; local_ai = local_ai->ai_next) {
                        if (local_ai->ai_family == remote_ai->ai_family) break;
                    }
                    if (!local_ai) {
                        if (any_addrinfos(&resolution_store)) continue;
                        if (in_progress_fds(arg->connection_attempt_fds_size)) break;
                        if (!resolution_store.is_all_finished) break;

                        /* Use a different family local address if no choice, this
                         * will cause EAFNOSUPPORT. */
                        rsock_syserr_fail_host_port(EAFNOSUPPORT, syscall, arg->local.host, arg->local.serv);
                    }
                }

                status = rsock_socket(remote_ai->ai_family, remote_ai->ai_socktype, remote_ai->ai_protocol);
                syscall = "socket(2)";

                if (status < 0) {
                    last_error.type = SYSCALL_ERROR;
                    last_error.ecode = errno;

                    if (any_addrinfos(&resolution_store)) continue;
                    if (in_progress_fds(arg->connection_attempt_fds_size)) break;
                    if (!resolution_store.is_all_finished) break;

                    if (local_status < 0) {
                        host = arg->local.host;
                        serv = arg->local.serv;
                    } else {
                        host = arg->remote.host;
                        serv = arg->remote.serv;
                    }
                    if (last_error.type == RESOLUTION_ERROR) {
                        rsock_raise_resolution_error(syscall, last_error.ecode);
                    } else {
                        rsock_syserr_fail_host_port(last_error.ecode, syscall, host, serv);
                    }
                }

                fd = status;

                if (local_ai) {
                    #if !defined(_WIN32) && !defined(__CYGWIN__)
                    status = 1;
                    if ((setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, (char*)&status, (socklen_t)sizeof(status))) < 0) {
                        rb_syserr_fail(errno, "setsockopt(2)");
                    }
                    #endif
                    status = bind(fd, local_ai->ai_addr, local_ai->ai_addrlen);
                    local_status = status;
                    syscall = "bind(2)";

                    if (status < 0) {
                        last_error.type = SYSCALL_ERROR;
                        last_error.ecode = errno;
                        close(fd);

                        if (any_addrinfos(&resolution_store)) continue;
                        if (in_progress_fds(arg->connection_attempt_fds_size)) break;
                        if (!resolution_store.is_all_finished) break;

                        if (local_status < 0) {
                            host = arg->local.host;
                            serv = arg->local.serv;
                        } else {
                            host = arg->remote.host;
                            serv = arg->remote.serv;
                        }
                        if (last_error.type == RESOLUTION_ERROR) {
                            rsock_raise_resolution_error(syscall, last_error.ecode);
                        } else {
                            rsock_syserr_fail_host_port(last_error.ecode, syscall, host, serv);
                        }
                    }
                }

                syscall = "connect(2)";

                if (any_addrinfos(&resolution_store) ||
                    in_progress_fds(arg->connection_attempt_fds_size) ||
                    !resolution_store.is_all_finished) {
                    socket_nonblock_set(fd);
                    status = connect(fd, remote_ai->ai_addr, remote_ai->ai_addrlen);
                    last_family = remote_ai->ai_family;
                } else {
                    if (!NIL_P(connect_timeout)) {
                        user_specified_connect_timeout_storage = rb_time_interval(connect_timeout);
                        user_specified_connect_timeout_at = &user_specified_connect_timeout_storage;
                    }

                    VALUE timeout =
                        (user_specified_connect_timeout_at && is_infinity(*user_specified_connect_timeout_at)) ?
                        Qnil : tv_to_seconds(user_specified_connect_timeout_at);
                    io = arg->io = rsock_init_sock(arg->self, fd);
                    status = rsock_connect(io, remote_ai->ai_addr, remote_ai->ai_addrlen, 0, timeout);
                }

                if (status == 0) {
                    connected_fd = fd;
                    break;
                }

                if (errno == EINPROGRESS) {
                    if (current_capacity == arg->connection_attempt_fds_size) {
                        current_capacity = reallocate_connection_attempt_fds(
                            &arg->connection_attempt_fds,
                            current_capacity,
                            additional_capacity
                        );
                    }
                    arg->connection_attempt_fds[arg->connection_attempt_fds_size] = fd;
                    (arg->connection_attempt_fds_size)++;

                    set_timeout_tv(&connection_attempt_delay_strage, 250, now);
                    connection_attempt_delay_expires_at = &connection_attempt_delay_strage;

                    if (!any_addrinfos(&resolution_store)) {
                        if (NIL_P(connect_timeout)) {
                            user_specified_connect_timeout_storage = (struct timeval){ -1, -1 };
                        } else {
                            struct timeval connect_timeout_tv = rb_time_interval(connect_timeout);
                            user_specified_connect_timeout_storage = add_ts_to_tv(connect_timeout_tv, now);
                        }
                        user_specified_connect_timeout_at = &user_specified_connect_timeout_storage;
                    }

                    break;
                }

                last_error.type = SYSCALL_ERROR;
                last_error.ecode = errno;

                if (NIL_P(io)) {
                    close(fd);
                } else {
                    rb_io_close(io);
                }

                if (any_addrinfos(&resolution_store)) continue;
                if (in_progress_fds(arg->connection_attempt_fds_size)) break;
                if (!resolution_store.is_all_finished) break;

                if (local_status < 0) {
                    host = arg->local.host;
                    serv = arg->local.serv;
                } else {
                    host = arg->remote.host;
                    serv = arg->remote.serv;
                }
                if (last_error.type == RESOLUTION_ERROR) {
                    rsock_raise_resolution_error(syscall, last_error.ecode);
                } else {
                    rsock_syserr_fail_host_port(last_error.ecode, syscall, host, serv);
                }
            }
        }

        if (connected_fd >= 0) break;

        ends_at = select_expires_at(
            &resolution_store,
            resolution_delay_expires_at,
            connection_attempt_delay_expires_at,
            user_specified_resolv_timeout_at,
            user_specified_connect_timeout_at,
            user_specified_open_timeout_at
        );
        if (ends_at) {
            delay = tv_to_timeout(ends_at, now);
            delay_p = &delay;
        } else {
            if (((resolution_store.v6.finished && !resolution_store.v4.finished) ||
                (resolution_store.v4.finished && !resolution_store.v6.finished)) &&
                !any_addrinfos(&resolution_store) &&
                !in_progress_fds(arg->connection_attempt_fds_size)) {
                /* A limited timeout is introduced to prevent select(2) from hanging when it is exclusively
                 * waiting for name resolution and write(2) failure occurs in a child thread. */
                delay.tv_sec = 0;
                delay.tv_usec = 50000;
                delay_p = &delay;
            } else {
                delay_p = NULL;
            }
        }

        nfds = 0;
        rb_fd_zero(&arg->writefds);
        if (in_progress_fds(arg->connection_attempt_fds_size)) {
            int n = 0;
            for (int i = 0; i < arg->connection_attempt_fds_size; i++) {
                int cfd = arg->connection_attempt_fds[i];
                if (cfd < 0) continue;
                if (cfd > n) n = cfd;
                rb_fd_set(cfd, &arg->writefds);
            }
            if (n > 0) n++;
            nfds = n;
        }

        rb_fd_zero(&arg->readfds);
        if (arg->family_size > 1) {
            rb_fd_set(hostname_resolution_waiter, &arg->readfds);

            if ((hostname_resolution_waiter + 1) > nfds) {
                nfds = hostname_resolution_waiter + 1;
            }
        }

        status = rb_thread_fd_select(nfds, &arg->readfds, &arg->writefds, NULL, delay_p);

        now = current_clocktime_ts();
        if (is_timeout_tv(resolution_delay_expires_at, now)) {
            resolution_delay_expires_at = NULL;
        }
        if (is_timeout_tv(connection_attempt_delay_expires_at, now)) {
            connection_attempt_delay_expires_at = NULL;
        }

        if (status < 0 && (errno && errno != EINTR)) rb_syserr_fail(errno, "select(2)");

        if (status > 0) {
            /* check for connection */
            if (in_progress_fds(arg->connection_attempt_fds_size)) {
                for (int i = 0; i < arg->connection_attempt_fds_size; i++) {
                    int fd = arg->connection_attempt_fds[i];
                    if (fd < 0 || !rb_fd_isset(fd, &arg->writefds)) continue;

                    int err;
                    socklen_t len = sizeof(err);

                    status = getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len);

                    if (status < 0) {
                        last_error.type = SYSCALL_ERROR;
                        last_error.ecode = errno;
                        close(fd);

                        if (any_addrinfos(&resolution_store)) continue;
                        if (in_progress_fds(arg->connection_attempt_fds_size)) break;
                        if (!resolution_store.is_all_finished) break;

                        if (local_status < 0) {
                            host = arg->local.host;
                            serv = arg->local.serv;
                        } else {
                            host = arg->remote.host;
                            serv = arg->remote.serv;
                        }
                        if (last_error.type == RESOLUTION_ERROR) {
                            rsock_raise_resolution_error(syscall, last_error.ecode);
                        } else {
                            rsock_syserr_fail_host_port(last_error.ecode, syscall, host, serv);
                        }
                    }

                    if (err == 0) { /* success */
                        remove_connection_attempt_fd(
                            arg->connection_attempt_fds,
                            &arg->connection_attempt_fds_size,
                            fd
                        );
                        connected_fd = fd;
                        break;
                    } else { /* fail */
                        close(fd);
                        remove_connection_attempt_fd(
                            arg->connection_attempt_fds,
                            &arg->connection_attempt_fds_size,
                            fd
                        );
                        last_error.type = SYSCALL_ERROR;
                        last_error.ecode = err;
                    }
                }

                if (connected_fd >= 0) break;

                if (!in_progress_fds(arg->connection_attempt_fds_size)) {
                    if (!any_addrinfos(&resolution_store) && resolution_store.is_all_finished) {
                        if (local_status < 0) {
                            host = arg->local.host;
                            serv = arg->local.serv;
                        } else {
                            host = arg->remote.host;
                            serv = arg->remote.serv;
                        }
                        if (last_error.type == RESOLUTION_ERROR) {
                            rsock_raise_resolution_error(syscall, last_error.ecode);
                        } else {
                            rsock_syserr_fail_host_port(last_error.ecode, syscall, host, serv);
                        }
                    }
                    connection_attempt_delay_expires_at = NULL;
                    user_specified_connect_timeout_at = NULL;
                }
            }

            /* check for hostname resolution */
            if (!resolution_store.is_all_finished && rb_fd_isset(hostname_resolution_waiter, &arg->readfds)) {
                while (true) {
                    resolved_type_size = read(
                        hostname_resolution_waiter,
                        resolved_type,
                        sizeof(resolved_type) - 1
                    );

                    if (resolved_type_size > 0) {
                        resolved_type[resolved_type_size] = '\0';

                        if (resolved_type[0] == IPV6_HOSTNAME_RESOLVED) {
                            resolution_store.v6.finished = true;

                            if (arg->getaddrinfo_entries[IPV6_ENTRY_POS]->err &&
                                arg->getaddrinfo_entries[IPV6_ENTRY_POS]->err != EAI_ADDRFAMILY) {
                                if (!resolution_store.v4.finished || resolution_store.v4.has_error) {
                                    last_error.type = RESOLUTION_ERROR;
                                    last_error.ecode = arg->getaddrinfo_entries[IPV6_ENTRY_POS]->err;
                                    syscall = "getaddrinfo(3)";
                                }
                                resolution_store.v6.has_error = true;
                            } else {
                                resolution_store.v6.ai = arg->getaddrinfo_entries[IPV6_ENTRY_POS]->ai;
                            }
                            if (resolution_store.v4.finished) {
                                resolution_store.is_all_finished = true;
                                resolution_delay_expires_at = NULL;
                                user_specified_resolv_timeout_at = NULL;
                                break;
                            }
                        } else if (resolved_type[0] == IPV4_HOSTNAME_RESOLVED) {
                            resolution_store.v4.finished = true;

                            if (arg->getaddrinfo_entries[IPV4_ENTRY_POS]->err) {
                                if (!resolution_store.v6.finished || resolution_store.v6.has_error) {
                                    last_error.type = RESOLUTION_ERROR;
                                    last_error.ecode = arg->getaddrinfo_entries[IPV4_ENTRY_POS]->err;
                                    syscall = "getaddrinfo(3)";
                                }
                                resolution_store.v4.has_error = true;
                            } else {
                                resolution_store.v4.ai = arg->getaddrinfo_entries[IPV4_ENTRY_POS]->ai;
                            }

                            if (resolution_store.v6.finished) {
                                resolution_store.is_all_finished = true;
                                resolution_delay_expires_at = NULL;
                                user_specified_resolv_timeout_at = NULL;
                                break;
                            }
                        } else {
                            /* Retry to read from hostname_resolution_waiter */
                        }
                    } else if (resolved_type_size < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                        errno = 0;
                        break;
                    } else {
                        /* Retry to read from hostname_resolution_waiter */
                    }

                    if (!resolution_store.v6.finished &&
                        resolution_store.v4.finished &&
                        !resolution_store.v4.has_error) {
                        set_timeout_tv(&resolution_delay_storage, 50, now);
                        resolution_delay_expires_at = &resolution_delay_storage;
                    }
                }
            }

            status = 0;
        }

        /* For cases where write(2) fails in child threads */
        if (!resolution_store.is_all_finished) {
            if (!resolution_store.v6.finished && arg->getaddrinfo_entries[IPV6_ENTRY_POS]->has_syserr) {
                resolution_store.v6.finished = true;

                if (arg->getaddrinfo_entries[IPV6_ENTRY_POS]->err) {
                    if (!resolution_store.v4.finished || resolution_store.v4.has_error) {
                        last_error.type = RESOLUTION_ERROR;
                        last_error.ecode = arg->getaddrinfo_entries[IPV6_ENTRY_POS]->err;
                        syscall = "getaddrinfo(3)";
                    }
                    resolution_store.v6.has_error = true;
                } else {
                    resolution_store.v6.ai = arg->getaddrinfo_entries[IPV6_ENTRY_POS]->ai;
                }

                if (resolution_store.v4.finished) {
                    resolution_store.is_all_finished = true;
                    resolution_delay_expires_at = NULL;
                    user_specified_resolv_timeout_at = NULL;
                }
            }
            if (!resolution_store.v4.finished && arg->getaddrinfo_entries[IPV4_ENTRY_POS]->has_syserr) {
                resolution_store.v4.finished = true;

                if (arg->getaddrinfo_entries[IPV4_ENTRY_POS]->err) {
                    if (!resolution_store.v6.finished || resolution_store.v6.has_error) {
                        last_error.type = RESOLUTION_ERROR;
                        last_error.ecode = arg->getaddrinfo_entries[IPV4_ENTRY_POS]->err;
                        syscall = "getaddrinfo(3)";
                    }
                    resolution_store.v4.has_error = true;
                } else {
                    resolution_store.v4.ai = arg->getaddrinfo_entries[IPV4_ENTRY_POS]->ai;
                }

                if (resolution_store.v6.finished) {
                    resolution_store.is_all_finished = true;
                    resolution_delay_expires_at = NULL;
                    user_specified_resolv_timeout_at = NULL;
                } else {
                    set_timeout_tv(&resolution_delay_storage, 50, now);
                    resolution_delay_expires_at = &resolution_delay_storage;
                }
            }
        }

        if (is_timeout_tv(user_specified_open_timeout_at, now)) rsock_raise_user_specified_timeout();

        if (!any_addrinfos(&resolution_store)) {
            if (!in_progress_fds(arg->connection_attempt_fds_size) &&
                resolution_store.is_all_finished) {
                if (local_status < 0) {
                    host = arg->local.host;
                    serv = arg->local.serv;
                } else {
                    host = arg->remote.host;
                    serv = arg->remote.serv;
                }
                if (last_error.type == RESOLUTION_ERROR) {
                    rsock_raise_resolution_error(syscall, last_error.ecode);
                } else {
                    rsock_syserr_fail_host_port(last_error.ecode, syscall, host, serv);
                }
            }

            if ((is_timeout_tv(user_specified_resolv_timeout_at, now) ||
                resolution_store.is_all_finished) &&
                (is_timeout_tv(user_specified_connect_timeout_at, now) ||
                !in_progress_fds(arg->connection_attempt_fds_size))) {
                rsock_raise_user_specified_timeout();
            }
        }
    }

    if (NIL_P(arg->io)) {
        /* create new instance */
        arg->io = rsock_init_sock(arg->self, connected_fd);
    }

    return arg->io;
}

static VALUE
fast_fallback_inetsock_cleanup(VALUE v)
{
    struct fast_fallback_inetsock_arg *arg = (void *)v;
    struct fast_fallback_getaddrinfo_shared *getaddrinfo_shared = arg->getaddrinfo_shared;

    if (arg->remote.res) {
        rb_freeaddrinfo(arg->remote.res);
        arg->remote.res = 0;
    }
    if (arg->local.res) {
        rb_freeaddrinfo(arg->local.res);
        arg->local.res = 0;
    }

    if (arg->wait != -1) close(arg->wait);

    if (getaddrinfo_shared) {
        if (getaddrinfo_shared->notify != -1) close(getaddrinfo_shared->notify);
        getaddrinfo_shared->notify = -1;

        int shared_need_free = 0;
        struct addrinfo *ais[arg->family_size];
        for (int i = 0; i < arg->family_size; i++) ais[i] = NULL;

        rb_nativethread_lock_lock(&getaddrinfo_shared->lock);
        {
            for (int i = 0; i < arg->family_size; i++) {
                struct fast_fallback_getaddrinfo_entry *getaddrinfo_entry = arg->getaddrinfo_entries[i];

                if (!getaddrinfo_entry) continue;

                if (--(getaddrinfo_entry->refcount) == 0) {
                    ais[i] = getaddrinfo_entry->ai;
                    getaddrinfo_entry->ai = NULL;
                }
            }
            if (--(getaddrinfo_shared->refcount) == 0) {
                shared_need_free = 1;
            }
        }
        rb_nativethread_lock_unlock(&getaddrinfo_shared->lock);

        for (int i = 0; i < arg->family_size; i++) {
            if (ais[i]) freeaddrinfo(ais[i]);
        }
        if (getaddrinfo_shared && shared_need_free) {
            free_fast_fallback_getaddrinfo_shared(&getaddrinfo_shared);
        }
    }

    int connection_attempt_fd;

    for (int i = 0; i < arg->connection_attempt_fds_size; i++) {
        connection_attempt_fd = arg->connection_attempt_fds[i];

        if (connection_attempt_fd >= 0) {
            int error = 0;
            socklen_t len = sizeof(error);
            getsockopt(connection_attempt_fd, SOL_SOCKET, SO_ERROR, &error, &len);
            if (error == 0) shutdown(connection_attempt_fd, SHUT_RDWR);
            close(connection_attempt_fd);
       }
    }

    if (arg->readfds.fdset) rb_fd_term(&arg->readfds);
    if (arg->writefds.fdset) rb_fd_term(&arg->writefds);

    if (arg->connection_attempt_fds) {
        free(arg->connection_attempt_fds);
        arg->connection_attempt_fds = NULL;
    }

    return Qnil;
}

VALUE
rsock_init_inetsock(
    VALUE self, VALUE remote_host, VALUE remote_serv,
    VALUE local_host, VALUE local_serv, int type,
    VALUE resolv_timeout, VALUE connect_timeout, VALUE open_timeout,
    VALUE fast_fallback, VALUE test_mode_settings
) {
    if (!NIL_P(open_timeout) && (!NIL_P(resolv_timeout) || !NIL_P(connect_timeout))) {
        rb_raise(rb_eArgError, "Cannot specify open_timeout along with connect_timeout or resolv_timeout");
    }

    if (type == INET_CLIENT && FAST_FALLBACK_INIT_INETSOCK_IMPL == 1 && RTEST(fast_fallback)) {
        struct rb_addrinfo *local_res = NULL;
        char *hostp, *portp;
        char hbuf[NI_MAXHOST], pbuf[NI_MAXSERV];
        int additional_flags = 0;
        hostp = raddrinfo_host_str(remote_host, hbuf, sizeof(hbuf), &additional_flags);
        portp = raddrinfo_port_str(remote_serv, pbuf, sizeof(pbuf), &additional_flags);

        if (!is_specified_ip_address(hostp)) {
            int target_families[2] = { 0, 0 };
            int resolving_family_size = 0;

            /*
             * Maybe also accept a local address
             */
            if (!NIL_P(local_host) || !NIL_P(local_serv)) {
                local_res = rsock_addrinfo(
                    local_host,
                    local_serv,
                    AF_UNSPEC,
                    SOCK_STREAM,
                    0,
                    0
                );

                struct addrinfo *tmp_p = local_res->ai;
                for (tmp_p; tmp_p != NULL; tmp_p = tmp_p->ai_next) {
                    if (target_families[0] == 0 && tmp_p->ai_family == AF_INET6) {
                        target_families[0] = AF_INET6;
                        resolving_family_size++;
                    }
                    if (target_families[1] == 0 && tmp_p->ai_family == AF_INET) {
                        target_families[1] = AF_INET;
                        resolving_family_size++;
                    }
                }
            }  else {
                resolving_family_size = 2;
                target_families[0] = AF_INET6;
                target_families[1] = AF_INET;
            }

            struct fast_fallback_inetsock_arg fast_fallback_arg;
            memset(&fast_fallback_arg, 0, sizeof(fast_fallback_arg));

            fast_fallback_arg.self = self;
            fast_fallback_arg.io = Qnil;
            fast_fallback_arg.remote.host = remote_host;
            fast_fallback_arg.remote.serv = remote_serv;
            fast_fallback_arg.remote.res = 0;
            fast_fallback_arg.local.host = local_host;
            fast_fallback_arg.local.serv = local_serv;
            fast_fallback_arg.local.res = local_res;
            fast_fallback_arg.type = type;
            fast_fallback_arg.resolv_timeout = resolv_timeout;
            fast_fallback_arg.connect_timeout = connect_timeout;
            fast_fallback_arg.open_timeout = open_timeout;
            fast_fallback_arg.hostp = hostp;
            fast_fallback_arg.portp = portp;
            fast_fallback_arg.additional_flags = additional_flags;

            int resolving_families[resolving_family_size];
            int resolving_family_index = 0;
            for (int i = 0; 2 > i; i++) {
                if (target_families[i] != 0) {
                    resolving_families[resolving_family_index] = target_families[i];
                    resolving_family_index++;
                }
            }
            fast_fallback_arg.families = resolving_families;
            fast_fallback_arg.family_size = resolving_family_size;
            fast_fallback_arg.test_mode_settings = test_mode_settings;

            rb_fd_init(&fast_fallback_arg.readfds);
            rb_fd_init(&fast_fallback_arg.writefds);

            return rb_ensure(init_fast_fallback_inetsock_internal, (VALUE)&fast_fallback_arg,
                             fast_fallback_inetsock_cleanup, (VALUE)&fast_fallback_arg);
        }
    }

    struct inetsock_arg arg;
    arg.self = self;
    arg.io = Qnil;
    arg.remote.host = remote_host;
    arg.remote.serv = remote_serv;
    arg.remote.res = 0;
    arg.local.host = local_host;
    arg.local.serv = local_serv;
    arg.local.res = 0;
    arg.type = type;
    arg.resolv_timeout = resolv_timeout;
    arg.connect_timeout = connect_timeout;
    arg.open_timeout = open_timeout;

    return rb_ensure(init_inetsock_internal, (VALUE)&arg,
                     inetsock_cleanup, (VALUE)&arg);
}

#endif

static ID id_numeric, id_hostname;

int
rsock_revlookup_flag(VALUE revlookup, int *norevlookup)
{
#define return_norevlookup(x) {*norevlookup = (x); return 1;}
    ID id;

    switch (revlookup) {
      case Qtrue:  return_norevlookup(0);
      case Qfalse: return_norevlookup(1);
      case Qnil: break;
      default:
        Check_Type(revlookup, T_SYMBOL);
        id = SYM2ID(revlookup);
        if (id == id_numeric) return_norevlookup(1);
        if (id == id_hostname) return_norevlookup(0);
        rb_raise(rb_eArgError, "invalid reverse_lookup flag: :%s", rb_id2name(id));
    }
    return 0;
#undef return_norevlookup
}

/*
 * call-seq:
 *   ipsocket.inspect   -> string
 *
 * Return a string describing this IPSocket object.
 */
static VALUE
ip_inspect(VALUE sock)
{
    VALUE str = rb_call_super(0, 0);
    rb_io_t *fptr = RFILE(sock)->fptr;
    union_sockaddr addr;
    socklen_t len = (socklen_t)sizeof addr;
    ID id;
    if (fptr && fptr->fd >= 0 &&
        getsockname(fptr->fd, &addr.addr, &len) >= 0 &&
        (id = rsock_intern_family(addr.addr.sa_family)) != 0) {
        VALUE family = rb_id2str(id);
        char hbuf[1024], pbuf[1024];
        long slen = RSTRING_LEN(str);
        const char last = (slen > 1 && RSTRING_PTR(str)[slen - 1] == '>') ?
            (--slen, '>') : 0;
        str = rb_str_subseq(str, 0, slen);
        rb_str_cat_cstr(str, ", ");
        rb_str_append(str, family);
        if (!rb_getnameinfo(&addr.addr, len, hbuf, sizeof(hbuf),
                            pbuf, sizeof(pbuf), NI_NUMERICHOST | NI_NUMERICSERV)) {
            rb_str_cat_cstr(str, ", ");
            rb_str_cat_cstr(str, hbuf);
            rb_str_cat_cstr(str, ", ");
            rb_str_cat_cstr(str, pbuf);
        }
        if (last) rb_str_cat(str, &last, 1);
    }
    return str;
}

/*
 * call-seq:
 *   ipsocket.addr([reverse_lookup]) => [address_family, port, hostname, numeric_address]
 *
 * Returns the local address as an array which contains
 * address_family, port, hostname and numeric_address.
 *
 * If +reverse_lookup+ is +true+ or +:hostname+,
 * hostname is obtained from numeric_address using reverse lookup.
 * Or if it is +false+, or +:numeric+,
 * hostname is the same as numeric_address.
 * Or if it is +nil+ or omitted, obeys to +ipsocket.do_not_reverse_lookup+.
 * See +Socket.getaddrinfo+ also.
 *
 *   TCPSocket.open("www.ruby-lang.org", 80) {|sock|
 *     p sock.addr #=> ["AF_INET", 49429, "hal", "192.168.0.128"]
 *     p sock.addr(true)  #=> ["AF_INET", 49429, "hal", "192.168.0.128"]
 *     p sock.addr(false) #=> ["AF_INET", 49429, "192.168.0.128", "192.168.0.128"]
 *     p sock.addr(:hostname)  #=> ["AF_INET", 49429, "hal", "192.168.0.128"]
 *     p sock.addr(:numeric)   #=> ["AF_INET", 49429, "192.168.0.128", "192.168.0.128"]
 *   }
 *
 */
static VALUE
ip_addr(int argc, VALUE *argv, VALUE sock)
{
    union_sockaddr addr;
    socklen_t len = (socklen_t)sizeof addr;
    int norevlookup;

    if (argc < 1 || !rsock_revlookup_flag(argv[0], &norevlookup))
        norevlookup = rb_io_mode(sock) & FMODE_NOREVLOOKUP;
    if (getsockname(rb_io_descriptor(sock), &addr.addr, &len) < 0)
        rb_sys_fail("getsockname(2)");
    return rsock_ipaddr(&addr.addr, len, norevlookup);
}

/*
 * call-seq:
 *   ipsocket.peeraddr([reverse_lookup]) => [address_family, port, hostname, numeric_address]
 *
 * Returns the remote address as an array which contains
 * address_family, port, hostname and numeric_address.
 * It is defined for connection oriented socket such as TCPSocket.
 *
 * If +reverse_lookup+ is +true+ or +:hostname+,
 * hostname is obtained from numeric_address using reverse lookup.
 * Or if it is +false+, or +:numeric+,
 * hostname is the same as numeric_address.
 * Or if it is +nil+ or omitted, obeys to +ipsocket.do_not_reverse_lookup+.
 * See +Socket.getaddrinfo+ also.
 *
 *   TCPSocket.open("www.ruby-lang.org", 80) {|sock|
 *     p sock.peeraddr #=> ["AF_INET", 80, "carbon.ruby-lang.org", "221.186.184.68"]
 *     p sock.peeraddr(true)  #=> ["AF_INET", 80, "carbon.ruby-lang.org", "221.186.184.68"]
 *     p sock.peeraddr(false) #=> ["AF_INET", 80, "221.186.184.68", "221.186.184.68"]
 *     p sock.peeraddr(:hostname) #=> ["AF_INET", 80, "carbon.ruby-lang.org", "221.186.184.68"]
 *     p sock.peeraddr(:numeric)  #=> ["AF_INET", 80, "221.186.184.68", "221.186.184.68"]
 *   }
 *
 */
static VALUE
ip_peeraddr(int argc, VALUE *argv, VALUE sock)
{
    union_sockaddr addr;
    socklen_t len = (socklen_t)sizeof addr;
    int norevlookup;

    if (argc < 1 || !rsock_revlookup_flag(argv[0], &norevlookup))
        norevlookup = rb_io_mode(sock) & FMODE_NOREVLOOKUP;
    if (getpeername(rb_io_descriptor(sock), &addr.addr, &len) < 0)
        rb_sys_fail("getpeername(2)");
    return rsock_ipaddr(&addr.addr, len, norevlookup);
}

/*
 * call-seq:
 *   ipsocket.recvfrom(maxlen)        => [mesg, ipaddr]
 *   ipsocket.recvfrom(maxlen, flags) => [mesg, ipaddr]
 *
 * Receives a message and return the message as a string and
 * an address which the message come from.
 *
 * _maxlen_ is the maximum number of bytes to receive.
 *
 * _flags_ should be a bitwise OR of Socket::MSG_* constants.
 *
 * ipaddr is the same as IPSocket#{peeraddr,addr}.
 *
 *   u1 = UDPSocket.new
 *   u1.bind("127.0.0.1", 4913)
 *   u2 = UDPSocket.new
 *   u2.send "uuuu", 0, "127.0.0.1", 4913
 *   p u1.recvfrom(10) #=> ["uuuu", ["AF_INET", 33230, "localhost", "127.0.0.1"]]
 *
 */
static VALUE
ip_recvfrom(int argc, VALUE *argv, VALUE sock)
{
    return rsock_s_recvfrom(sock, argc, argv, RECV_IP);
}

/*
 * call-seq:
 *   IPSocket.getaddress(host)        => ipaddress
 *
 * Lookups the IP address of _host_.
 *
 *   require 'socket'
 *
 *   IPSocket.getaddress("localhost")     #=> "127.0.0.1"
 *   IPSocket.getaddress("ip6-localhost") #=> "::1"
 *
 */
static VALUE
ip_s_getaddress(VALUE obj, VALUE host)
{
    union_sockaddr addr;
    struct rb_addrinfo *res = rsock_addrinfo(host, Qnil, AF_UNSPEC, SOCK_STREAM, 0, 0);
    socklen_t len = res->ai->ai_addrlen;

    /* just take the first one */
    memcpy(&addr, res->ai->ai_addr, len);
    rb_freeaddrinfo(res);

    return rsock_make_ipaddr(&addr.addr, len);
}

void
rsock_init_ipsocket(void)
{
    /*
     * Document-class: IPSocket < BasicSocket
     *
     * IPSocket is the super class of TCPSocket and UDPSocket.
     */
    rb_cIPSocket = rb_define_class("IPSocket", rb_cBasicSocket);
    rb_define_method(rb_cIPSocket, "inspect", ip_inspect, 0);
    rb_define_method(rb_cIPSocket, "addr", ip_addr, -1);
    rb_define_method(rb_cIPSocket, "peeraddr", ip_peeraddr, -1);
    rb_define_method(rb_cIPSocket, "recvfrom", ip_recvfrom, -1);
    rb_define_singleton_method(rb_cIPSocket, "getaddress", ip_s_getaddress, 1);
    rb_undef_method(rb_cIPSocket, "getpeereid");

    id_numeric = rb_intern_const("numeric");
    id_hostname = rb_intern_const("hostname");
}
