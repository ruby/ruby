#include "rubysocket.h"

VALUE rb_cSocketCredentials;

#define STRUCT_INDEX_PID 0
#define STRUCT_INDEX_UID 1
#define STRUCT_INDEX_GID 2
#define STRUCT_INDEX_EUID 3
#define STRUCT_INDEX_EGID 4
#define STRUCT_INDEX_GROUPS 5
#define STRUCT_INDEX_SOURCE 6

static VALUE sym_ucred, sym_cmsgcred, sym_sockcred, sym_sockpeercred,
              sym_xucred;

static VALUE
socket_credentials_new(void)
{
    return rb_struct_new(rb_cSocketCredentials,
                         Qnil, Qnil, Qnil, Qnil, Qnil, Qnil, Qnil);
}

#if defined(HAVE_LINUX_STYLE_UCRED)
static VALUE
credentials_from_ucred(struct ucred *cred)
{
    VALUE result = socket_credentials_new();
    RSTRUCT_SET(result, STRUCT_INDEX_PID, PIDT2NUM(cred->pid));
    RSTRUCT_SET(result, STRUCT_INDEX_UID, UIDT2NUM(cred->uid));
    RSTRUCT_SET(result, STRUCT_INDEX_GID, GIDT2NUM(cred->gid));
    /* On Linux, at least:
     *   - A process can send _either_ its uid or euid in SCM_CREDENTIALS
     *   - getsockopt(SO_PEERCRED) gets euid, not uid
     *
     * The existing test-cases for SCM_CREDENTIALS asserted that "uid="
     * was printed, and for SO_PEERCRED, it asserted "euid=".
     *
     * I think a sensible thing to do therefore is to set both uid and
     * euid to the credential uid. */
    RSTRUCT_SET(result, STRUCT_INDEX_EUID, UIDT2NUM(cred->uid));
    RSTRUCT_SET(result, STRUCT_INDEX_EGID, UIDT2NUM(cred->gid));

    RSTRUCT_SET(result, STRUCT_INDEX_SOURCE, sym_ucred);
    return result;
}

static void
credentials_to_ucred(VALUE credstruct, struct ucred *cred)
{
    cred->pid = NUM2PIDT(RSTRUCT_GET(credstruct, STRUCT_INDEX_PID));

    /* Inverse of above - set cred->uid from _either_ uid or euid if
     * either one is provided */
    VALUE uid = RSTRUCT_GET(credstruct, STRUCT_INDEX_UID);
    VALUE euid = RSTRUCT_GET(credstruct, STRUCT_INDEX_EUID);
    if (RB_TEST(euid)) {
        cred->uid = NUM2UIDT(euid);
    } else {
        cred->uid = NUM2UIDT(uid);
    }

    VALUE gid = RSTRUCT_GET(credstruct, STRUCT_INDEX_GID);
    VALUE egid = RSTRUCT_GET(credstruct, STRUCT_INDEX_EGID);
    if (RB_TEST(egid)) {
        cred->gid = NUM2UIDT(egid);
    } else {
        cred->gid = NUM2UIDT(gid);
    }
}
#endif

#if defined(HAVE_TYPE_STRUCT_CMSGCRED)
static VALUE
credentials_from_cmsgcred(struct cmsgcred *cred)
{
    VALUE result = socket_credentials_new();
    RSTRUCT_SET(result, STRUCT_INDEX_PID, PIDT2NUM(cred->cmcred_pid));
    RSTRUCT_SET(result, STRUCT_INDEX_UID, UIDT2NUM(cred->cmcred_uid));
    RSTRUCT_SET(result, STRUCT_INDEX_GID, GIDT2NUM(cred->cmcred_gid));
    RSTRUCT_SET(result, STRUCT_INDEX_EUID, UIDT2NUM(cred->cmcred_euid));
    /* struct cmsgcred does not have egid, so just set it as == gid */
    RSTRUCT_SET(result, STRUCT_INDEX_EGID, GIDT2NUM(cred->cmcred_gid));


    VALUE group_ary = rb_ary_new();
    for (int i = 0; i < cred->cmcred_ngroups; i++) {
        rb_ary_push(group_ary, GIDT2NUM(cred->cmcred_groups[i]));
    };
    RSTRUCT_SET(result, STRUCT_INDEX_GROUPS, group_ary);
    RSTRUCT_SET(result, STRUCT_INDEX_SOURCE, sym_cmsgcred);
    return result;
}
#endif

#if defined(HAVE_TYPE_STRUCT_SOCKCRED)
static VALUE
credentials_from_sockcred(struct sockcred *cred)
{
    VALUE result = socket_credentials_new();
    RSTRUCT_SET(result, STRUCT_INDEX_UID, UIDT2NUM(cred->sc_uid));
    RSTRUCT_SET(result, STRUCT_INDEX_GID, GIDT2NUM(cred->sc_gid));
    RSTRUCT_SET(result, STRUCT_INDEX_EUID, UIDT2NUM(cred->sc_euid));
    RSTRUCT_SET(result, STRUCT_INDEX_EGID, GIDT2NUM(cred->sc_egid));

    VALUE group_ary = rb_ary_new();
    for (int i = 0; i < cred->sc_ngroups && i < CMGROUP_MAX; i++) {
        rb_ary_push(group_ary, GIDT2NUM(cred->sc_groups[i]));
    };
    RSTRUCT_SET(result, STRUCT_INDEX_GROUPS, group_ary);
    RSTRUCT_SET(result, STRUCT_INDEX_SOURCE, sym_sockcred);
    return result;
}
#endif

#if defined(HAVE_TYPE_STRUCT_SOCKPEERCRED)
static VALUE
credentials_from_sockpeercred(struct sockpeercred *cred)
{
    VALUE result = socket_credentials_new();
    RSTRUCT_SET(result, STRUCT_INDEX_PID, PIDT2NUM(cred->pid));
    RSTRUCT_SET(result, STRUCT_INDEX_UID, UIDT2NUM(cred->uid));
    RSTRUCT_SET(result, STRUCT_INDEX_GID, GIDT2NUM(cred->gid));
    RSTRUCT_SET(result, STRUCT_INDEX_EUID, UIDT2NUM(cred->uid));
    RSTRUCT_SET(result, STRUCT_INDEX_EGID, GIDT2NUM(cred->gid));
    RSTRUCT_SET(result, STRUCT_INDEX_SOURCE, sym_sockpeercred);
    return result;
}
#endif

#if defined(HAVE_FREEBSD_STYLE_XUCRED)
static VALUE
credentials_from_xucred(struct xucred *cred)
{
    VALUE result = socket_credentials_new();
    RSTRUCT_SET(result, STRUCT_INDEX_UID, UIDT2NUM(cred->cr_uid));
    RSTRUCT_SET(result, STRUCT_INDEX_EUID, UIDT2NUM(cred->cr_uid));

    VALUE group_ary = rb_ary_new();
    for (int i = 0; i < cred->cr_ngroups && i < NGROUPS_MAX; i++) {
        rb_ary_push(group_ary, GIDT2NUM(cred->cr_groups[i]));
    }
    RSTRUCT_SET(result, STRUCT_INDEX_GROUPS, group_ary);
    RSTRUCT_SET(result, STRUCT_INDEX_SOURCE, sym_xucred);
    return result;
}
#endif

/*
 * call-seq:
 *   Socket::Credentials.from_ancillary_data(level, type, data, local_creds_enabled: false, socket: nil) => credentials
 *
 * Creates a new instance of Socket::Credentials, from the supplied ancillary
 * data obtained via _BasicSocket#recvmsg_. If the ancillary data type is not
 * SCM_CREDS or SCM_CREDENTIALS, or if passing credentials through ancillary
 * data is not supported on this platform, then nil is returned.
 *
 * If _socket_ is passed in as a keyword argument, it is used to resolve an
 * ambiguity in the format of the ancillary data which arises on platforms
 * which support both the LOCAL_CREDS socket option and passing credentials
 * explicitly with ancillary data of type _struct cmsgcred_ (notably, FreeBSD
 * is such a platform). In this case, it is not always possible to know whether
 * an ancillary message contains a _struct cmsgcred_, or a _struct sockcred_.
 * If the _socket_ is provided, this method will query the state of the
 * LOCAL_CREDS socket option to resolve this ambiguity; otherwise, a guess will
 * be made based on the size of the structure.
 *
 * It is also possible to instead pass _local_creds_enabled_ in instead; if true,
 * this method assumes that the LOCAL_CREDS socket option was set on the socket
 * that received this ancillary data.
 *
 */
static VALUE
credentials_s_from_ancdata(int argc, VALUE *argv, VALUE klass)
{
    VALUE MAYBE_UNUSED(socket_arg), MAYBE_UNUSED(local_creds_enabled_arg);
    VALUE vlevel, vtype, data;
    VALUE kwarg_hash = Qnil;
    ID kwarg_keys[2] = {
      rb_intern("local_creds_enabled"),
      rb_intern("socket"),
    };
    VALUE kwarg_values[2] = { Qundef, Qundef };

    rb_scan_args(argc, argv, "3:", &vlevel, &vtype, &data, &kwarg_hash);
    if (RB_TEST(kwarg_hash)) {
        rb_get_kwargs(kwarg_hash, kwarg_keys, 0, 2, kwarg_values);
    }
    local_creds_enabled_arg = kwarg_values[0];
    socket_arg = kwarg_values[1];

    int MAYBE_UNUSED(level) = RB_NUM2INT(vlevel);
    int MAYBE_UNUSED(type) = RB_NUM2INT(vtype);
    if (!RB_TYPE_P(data, T_STRING)) {
        rb_raise(rb_eTypeError, "ancdata not a string");
    }

#if defined(SCM_CREDENTIALS) && defined(HAVE_LINUX_STYLE_UCRED)
    /* GNU/Linux - credentials from cmsg's come in an SCM_CREDENTIALS msg
     * and contain a struct ucred */
    if (level == SOL_SOCKET && type == SCM_CREDENTIALS &&
        RSTRING_LEN(data) == sizeof(struct ucred)) {

        struct ucred *cred = (struct ucred *)RSTRING_PTR(data);
        return credentials_from_ucred(cred);
    }
#endif

    /* FreeBSD - the structure of the credentials in a cmsg actually depends
     * on whether LOCAL_CREDS socket option is set on the socket - if so,
     * (i.e. the receiver has requested to receive sender credentials in a cmsg),
     * credentials come in a struct sockcred. If not, and the sender has explicitly
     * pushed credentials by sending a SCM_CREDS cmsg on its side, then the creds
     * come in a struct cmsgcred.
     *
     * It would be _almost_ possible to differentiate the two by the size of the cmsg
     * buffer, but struct sockcred has a flexible array member for storing the groups,
     * so it's possible to have the right number of groups so as to make the cmsg size
     * == sizeof(struct cmsgcred).
     *
     * So - technically, we need to be told what to do in this case.
     *   - If the local_creds_enabled kwarg is true, we assume the cmsg is struct sockcred.
     *   - If the socket kwarg is passed, we call getsockopt to find out if LOCAL_CREDS
     *     is set
     *   - Otherwise we just guess from the size.
     * */

#if defined(SCM_CREDS)
    if (level == SOL_SOCKET && type == SCM_CREDS) {
        bool local_creds_enabled;
#if defined(LOCAL_CREDS)
        if (!RB_NIL_OR_UNDEF_P(local_creds_enabled_arg)) {
            local_creds_enabled = RB_TEST(local_creds_enabled_arg);
        } else if (!RB_NIL_OR_UNDEF_P(socket_arg)) {
            VALUE sockopt = rb_funcall(socket_arg, rb_intern("getsockopt"), 2,
                                       RB_INT2NUM(SOL_LOCAL), RB_INT2NUM(LOCAL_CREDS));
            VALUE sockopt_value = rb_funcall(sockopt, rb_intern("int"), 0);
            local_creds_enabled = RB_NUM2INT(sockopt_value) == 1;
        } else {
#if defined(HAVE_TYPE_STRUCT_CMSGCRED)
            local_creds_enabled = RSTRING_LEN(data) != sizeof(struct cmsgcred);
#else
            local_creds_enabled = true;
#endif
        }
#else
        local_creds_enabled = false;
#endif

        if (local_creds_enabled) {
#if defined(HAVE_TYPE_STRUCT_SOCKCRED)
            if (RSTRING_LEN(data) >= (long)SOCKCREDSIZE(0)) {
                struct sockcred *cred = (struct sockcred *)RSTRING_PTR(data);
                if (RSTRING_LEN(data) == SOCKCREDSIZE(cred->sc_ngroups)) {
                    return credentials_from_sockcred(cred);
                }
            }
#endif
        } else {
#if defined(HAVE_TYPE_STRUCT_CMSGCRED)
            if (RSTRING_LEN(data) == sizeof(struct cmsgcred)) {
                struct cmsgcred *cred = (struct cmsgcred *)RSTRING_PTR(data);
                return credentials_from_cmsgcred(cred);
            }
#endif
        }
    }
#endif

    /* If we fell through to here we couldn't figure out what structure to unmarshal
     * the cmsg data into. */
    return Qnil;
}

/*
 * call-seq:
 *   Socket::Credentials.from_sockopt(level, type, data) => credentials
 *
 * Constructs a new instace of Socket::Credentials from the provided socket option
 * data. If the data is the result of fetching the SO_PEERCRED or LOCAL_PEERCRED
 * socket option, this method will interpret that data as a Socket::Credentials instance.
 *
 */
static VALUE
credentials_s_from_sockopt(VALUE klass, VALUE vlevel, VALUE vtype, VALUE data)
{
    int level = RB_NUM2INT(vlevel);
    int type = RB_NUM2INT(vtype);
    if (!RB_TYPE_P(data, T_STRING)) {
        rb_raise(rb_eTypeError, "sockopt data not a string");
    }

#if defined(SOL_SOCKET) && defined(SO_PEERCRED)
    if (level == SOL_SOCKET && type == SO_PEERCRED) {
#if defined(HAVE_TYPE_STRUCT_SOCKPEERCRED)
        /* OpenBSD puts a struct sockpeercred in here */
        if (RSTRING_LEN(data) == sizeof(struct sockpeercred)) {
            struct sockpeercred *cred = (struct sockpeercred *)RSTRING_PTR(data);
            return credentials_from_sockpeercred(cred);
        }
#elif defined(HAVE_LINUX_STYLE_UCRED)
        /* GNU/Linux puts a struct ucred in here */
        if (RSTRING_LEN(data) == sizeof(struct ucred)) {
            struct ucred *cred = (struct ucred *)RSTRING_PTR(data);
            return credentials_from_ucred(cred);
        }
#endif
    }
#endif
#if defined(SOL_LOCAL) && defined(LOCAL_PEERCRED)
    if (level == SOL_LOCAL && type == LOCAL_PEERCRED) {
#if defined(HAVE_FREEBSD_STYLE_XUCRED)
        /* FreeBSD & MacOS */
        if (RSTRING_LEN(data) == sizeof(struct xucred)) {
            struct xucred *cred = (struct xucred *)RSTRING_PTR(data);
            if (cred->cr_version == XUCRED_VERSION) {
                return credentials_from_xucred(cred);
            }
        }
#endif
    }

#endif

    return Qnil;
}

/*
 * call-seq:
 *   Socket::Credentials.for_process => credentials
 *
 * Constructs a new Socket::Credentials instance containing values from the
 * current process. This is useful to subsequently convert to a
 * Socket::AncillaryData instance (with #as_ancillary_data), and pass this
 * credential to a remote peer.
 *
 *   s1, s2 = UNIXSocket.pair
 *   # Linux needs this sockopt
 *   s2.setsockopt :SOCKET, :PASSCRED, 1 if defined?(Socket::SO_PASSCRED)
 *   creds_out = Socket::Credentials.for_process.as_ancillary_data
 *   s1.sendmsg "hello", 0, nil, creds_out
 *   _, _, _, creds_in = s2.recvmsg
 *
 *   p creds_in
 *   => #<Socket::AncillaryData: UNIX SOCKET CREDENTIALS pid=316811 uid=1000 euid=1000 gid=1000 egid=1000 (ucred)
 *   p creds_in.credentials
 *   => #<Socket::Credentials: pid=316811 uid=1000 euid=1000 gid=1000 egid=1000 (ucred)>
 */
static VALUE
credentials_s_for_process(VALUE klass)
{
    VALUE creds = socket_credentials_new();
    RSTRUCT_SET(creds, STRUCT_INDEX_PID,
                rb_funcall(rb_mProcess, rb_intern("pid"), 0));
    RSTRUCT_SET(creds, STRUCT_INDEX_UID,
                rb_funcall(rb_mProcess, rb_intern("uid"), 0));
    RSTRUCT_SET(creds, STRUCT_INDEX_GID,
                rb_funcall(rb_mProcess, rb_intern("gid"), 0));
    RSTRUCT_SET(creds, STRUCT_INDEX_EUID,
                rb_funcall(rb_mProcess, rb_intern("euid"), 0));
    RSTRUCT_SET(creds, STRUCT_INDEX_EGID,
                rb_funcall(rb_mProcess, rb_intern("egid"), 0));

    if (rb_respond_to(rb_mProcess, rb_intern("groups"))) {
    RSTRUCT_SET(creds, STRUCT_INDEX_GROUPS,
                rb_funcall(rb_mProcess, rb_intern("groups"), 0));
    }

    return creds;
}

/*
 * call-seq:
 *   credentials.as_ancillary_data => ancillarydata
 *
 * Converts this Socket::Credentials instance into an ancillary data message, which
 * can be passed into BasicSocket#sendmsg to identify this process to a remote peer.
 *
 * On Linux, it is possible for a sufficiently privileged process to claim to have
 * any credentials; otherwise, the kernel will validate the passed credentials and
 * an exception will be raised if they do not match the pid/uid/gid of the current
 * process.
 *
 * On FreeBSD, the contents of the ancillary data is actually totally ignored, and
 * the kernel always fills it in with the credentials of the sending process. Thus,
 * the returned Socket::AncillaryData from this method on FreeBSD will actually
 * just be an empty buffer.
 *
 *   cr = Socket::Credentials.new.tap { |c| c.pid = 1; c.uid = 2; c.gid = 3; }
 *   p cr.as_ancillary_data
 *   # On Linux
 *   => #<Socket::AncillaryData: UNIX SOCKET CREDENTIALS pid=1 uid=2 euid=2 gid=3 egid=3 (ucred)>
 *   # On FreeBSD
 *   => #<Socket::AncillaryData: UNIX SOCKET CREDS pid=0 uid=0 euid=0 gid=0 egid=0 groups= (cmsgcred)>
 */
#if defined(HAVE_STRUCT_MSGHDR_MSG_CONTROL) && defined(SCM_CREDENTIALS) && \
    defined(HAVE_LINUX_STYLE_UCRED) && defined(HAVE_STRUCT_MSGHDR_MSG_CONTROL)
static VALUE
credentials_as_ancillary_data(VALUE self)
{
    /* GNU/Linux supports passing explicit credentials as ancillary data, which can be different
     * to the processes real values if the process has sufficient privileges */
    VALUE data_str = rb_str_buf_new(sizeof(struct ucred));
    rb_str_set_len(data_str, sizeof(struct ucred));
    credentials_to_ucred(self, (struct ucred *)RSTRING_PTR(data_str));

    return rb_funcall(rb_cAncillaryData, rb_intern("new"), 4,
                      RB_INT2NUM(AF_UNIX), RB_INT2NUM(SOL_SOCKET),
                      RB_INT2NUM(SCM_CREDENTIALS), data_str);
}
#elif defined(HAVE_STRUCT_MSGHDR_MSG_CONTROL) && defined(SCM_CREDS) && \
      defined(HAVE_TYPE_STRUCT_CMSGCRED) && defined(HAVE_STRUCT_MSGHDR_MSG_CONTROL)
static VALUE
credentials_as_ancillary_data(VALUE self)
{
    /* FreeBSD ignores anything set in the creds. Passing a SCM_CREDS message can only send
     * the current processes real credentials. The docs say to zero out the buffer, although
     * it doesn't seem to be strictly nescessary. */
    VALUE data_str = rb_str_buf_new(sizeof(struct cmsgcred));
    rb_str_set_len(data_str, sizeof(struct cmsgcred));
    memset(RSTRING_PTR(data_str), 0, sizeof(struct cmsgcred));

    return rb_funcall(rb_cAncillaryData, rb_intern("new"), 4,
                      RB_INT2NUM(AF_UNIX), RB_INT2NUM(SOL_SOCKET),
                      RB_INT2NUM(SCM_CREDS), data_str);
}
#else
#define credentials_as_ancillary_data rb_f_notimplement
#endif

VALUE
rsock_credentials_inspect_fragment(VALUE creds)
{
    VALUE pid = RSTRUCT_GET(creds, STRUCT_INDEX_PID);
    VALUE uid = RSTRUCT_GET(creds, STRUCT_INDEX_UID);
    VALUE euid = RSTRUCT_GET(creds, STRUCT_INDEX_EUID);
    VALUE gid = RSTRUCT_GET(creds, STRUCT_INDEX_GID);
    VALUE egid = RSTRUCT_GET(creds, STRUCT_INDEX_EGID);
    VALUE groups = RSTRUCT_GET(creds, STRUCT_INDEX_GROUPS);
    VALUE source_struct = RSTRUCT_GET(creds, STRUCT_INDEX_SOURCE);

    VALUE ret = rb_str_new(NULL, 0);

    if (RB_TEST(pid)) rb_str_catf(ret, " pid=%"PRIsVALUE, pid);
    if (RB_TEST(uid)) rb_str_catf(ret, " uid=%"PRIsVALUE, uid);
    if (RB_TEST(euid)) rb_str_catf(ret, " euid=%"PRIsVALUE, euid);
    if (RB_TEST(gid)) rb_str_catf(ret, " gid=%"PRIsVALUE, gid);
    if (RB_TEST(egid)) rb_str_catf(ret, " egid=%"PRIsVALUE, egid);
    if (RB_TEST(groups)) {
      rb_str_catf(ret, " groups=%"PRIsVALUE, rb_ary_join(groups, rb_str_new_cstr(",")));
    }
    if (RB_TEST(source_struct)) {
      rb_str_catf(ret, " (%"PRIsVALUE")", rb_sym2str(source_struct));
    }

    return ret;
}

/*
 * call-seq:
 *   credentials.inspect
 *
 * Returns a human-readable description of the credentials
 *
 *   p Socket::Credentials.for_process.inspect
 *   => "#<Socket::Credentials: pid=316811 uid=1000 euid=1000 gid=1000 egid=1000 groups=10,36,39,63,100,104,135,1000>"
 */
static VALUE
credentials_inspect(VALUE self)
{
    return rb_sprintf("#<%s:%"PRIsVALUE">",
                      rb_obj_classname(self),
                      rsock_credentials_inspect_fragment(self));
}

void
rsock_init_credentials(void)
{
    /*
     * Document-class: Socket::Credentials
     *
     * Socket::Credentials represents the identity of a process, in the context
     * of a local Unix domain socket. Depending on the platform, such credentials
     * can be obtained from a remote peer in a number of different ways:
     *
     *   * By checking reading a socket option, like SO_PEERCRED (Linux, OpenBSD),
     *     or LOCAL_PEERCRED (FreeBSD, MacOS)
     *   * By setting a socket option like SO_PASSCRED (Linux) or LOCAL_CREDS (FreeBSD),
     *     which asks the system to automatically include the credentials of the remote
     *     end of the socket in an ancillary message of type SCM_CREDS (FreeBSD) or
     *     SCM_CREDENTIALS (Linux)
     *   * By the remote end of a connection explicitly sending ancillary data of type
     *     SCM_CREDS or SCM_CREDENTIALS containing credentials (such credentials are
     *     validated by the kernel to ensure they can only be sent by a processes that
     *     holds them).
     *
     *  Depending on the platform, such credentials might come in a number of different
     *  underlying structures, such as _struct ucred_, _struct cmsgcred_, _struct sockcred_,
     *  _struct sockpeercred_, or _struct xucred_. If a field is not supported on the
     *  current platform, it is represented as nil in Socket::Credentials.
     */
    rb_cSocketCredentials = rb_struct_define_under(rb_cSocket, "Credentials",
                                                  "pid", "uid", "gid",
                                                  "euid", "egid", "groups", "source",
                                                  NULL);
    rb_define_singleton_method(rb_cSocketCredentials, "from_ancillary_data",
                               credentials_s_from_ancdata, -1);
    rb_define_singleton_method(rb_cSocketCredentials, "from_sockopt",
                               credentials_s_from_sockopt, 3);
    rb_define_singleton_method(rb_cSocketCredentials, "for_process",
                               credentials_s_for_process, 0);
    rb_define_method(rb_cSocketCredentials, "inspect", credentials_inspect, 0);
    rb_define_method(rb_cSocketCredentials, "as_ancillary_data", credentials_as_ancillary_data, 0);

    sym_ucred = rb_id2sym(rb_intern("ucred"));
    rb_gc_register_mark_object(sym_ucred);
    sym_cmsgcred = rb_id2sym(rb_intern("cmsgcred"));
    rb_gc_register_mark_object(sym_cmsgcred);
    sym_sockcred = rb_id2sym(rb_intern("sockcred"));
    rb_gc_register_mark_object(sym_sockcred);
    sym_sockpeercred = rb_id2sym(rb_intern("sockpeercred"));
    rb_gc_register_mark_object(sym_sockpeercred);
    sym_xucred = rb_id2sym(rb_intern("xucred"));
    rb_gc_register_mark_object(sym_xucred);
}
