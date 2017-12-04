#include "rubysocket.h"

#ifdef HAVE_GETIFADDRS

/*
 * ifa_flags is usually unsigned int.
 * However it is uint64_t on SunOS 5.11 (OpenIndiana).
 */
#ifdef HAVE_LONG_LONG
typedef unsigned LONG_LONG ifa_flags_t;
#define PRIxIFAFLAGS PRI_LL_PREFIX"x"
#define IFAFLAGS2NUM(flags) ULL2NUM(flags)
#else
typedef unsigned int ifa_flags_t;
#define PRIxIFAFLAGS "x"
#define IFAFLAGS2NUM(flags) UINT2NUM(flags)
#endif

VALUE rb_cSockIfaddr;

typedef struct rb_ifaddr_tag rb_ifaddr_t;
typedef struct rb_ifaddr_root_tag rb_ifaddr_root_t;

struct rb_ifaddr_tag {
    int ord;
    struct ifaddrs *ifaddr;
};

struct rb_ifaddr_root_tag {
    int refcount;
    int numifaddrs;
    rb_ifaddr_t ary[1];
};

static rb_ifaddr_root_t *
get_root(const rb_ifaddr_t *ifaddr)
{
    return (rb_ifaddr_root_t *)((char *)&ifaddr[-ifaddr->ord] -
                                offsetof(rb_ifaddr_root_t, ary));
}

static void
ifaddr_free(void *ptr)
{
    rb_ifaddr_t *ifaddr = ptr;
    rb_ifaddr_root_t *root = get_root(ifaddr);
    root->refcount--;
    if (root->refcount == 0) {
        freeifaddrs(root->ary[0].ifaddr);
        xfree(root);
    }
}

static size_t
ifaddr_memsize(const void *ptr)
{
    size_t size = offsetof(rb_ifaddr_root_t, ary);
    const rb_ifaddr_t *ifaddr;
    ifaddr = ptr;
    if (ifaddr->ord == 0) size = sizeof(rb_ifaddr_root_t);
    size += sizeof(struct ifaddrs);
    return size;
}

static const rb_data_type_t ifaddr_type = {
    "socket/ifaddr",
    {0, ifaddr_free, ifaddr_memsize,},
};

static inline rb_ifaddr_t *
check_ifaddr(VALUE self)
{
      return rb_check_typeddata(self, &ifaddr_type);
}

static rb_ifaddr_t *
get_ifaddr(VALUE self)
{
    rb_ifaddr_t *rifaddr = check_ifaddr(self);

    if (!rifaddr) {
        rb_raise(rb_eTypeError, "uninitialized ifaddr");
    }
    return rifaddr;
}

static VALUE
rsock_getifaddrs(void)
{
    int ret;
    int numifaddrs, i;
    struct ifaddrs *ifaddrs, *ifa;
    rb_ifaddr_root_t *root;
    VALUE result, addr;

    ret = getifaddrs(&ifaddrs);
    if (ret == -1)
        rb_sys_fail("getifaddrs");

    if (!ifaddrs) {
	return rb_ary_new();
    }

    numifaddrs = 0;
    for (ifa = ifaddrs; ifa != NULL; ifa = ifa->ifa_next)
        numifaddrs++;

    addr = TypedData_Wrap_Struct(rb_cSockIfaddr, &ifaddr_type, 0);
    root = xmalloc(offsetof(rb_ifaddr_root_t, ary) + numifaddrs * sizeof(rb_ifaddr_t));
    root->refcount = 0;
    root->numifaddrs = numifaddrs;

    ifa = ifaddrs;
    for (i = 0; i < numifaddrs; i++) {
        root->ary[i].ord = i;
        root->ary[i].ifaddr = ifa;
        ifa = ifa->ifa_next;
    }
    RTYPEDDATA_DATA(addr) = &root->ary[0];
    root->refcount++;

    result = rb_ary_new2(numifaddrs);
    rb_ary_push(result, addr);
    for (i = 1; i < numifaddrs; i++) {
	addr = TypedData_Wrap_Struct(rb_cSockIfaddr, &ifaddr_type, &root->ary[i]);
	root->refcount++;
	rb_ary_push(result, addr);
    }

    return result;
}

/*
 * call-seq:
 *   ifaddr.name => string
 *
 * Returns the interface name of _ifaddr_.
 */

static VALUE
ifaddr_name(VALUE self)
{
    rb_ifaddr_t *rifaddr = get_ifaddr(self);
    struct ifaddrs *ifa = rifaddr->ifaddr;
    return rb_str_new_cstr(ifa->ifa_name);
}

#ifdef HAVE_IF_NAMETOINDEX
/*
 * call-seq:
 *   ifaddr.ifindex => integer
 *
 * Returns the interface index of _ifaddr_.
 */

static VALUE
ifaddr_ifindex(VALUE self)
{
    rb_ifaddr_t *rifaddr = get_ifaddr(self);
    struct ifaddrs *ifa = rifaddr->ifaddr;
    unsigned int ifindex = if_nametoindex(ifa->ifa_name);
    if (ifindex == 0) {
        rb_raise(rb_eArgError, "invalid interface name: %s", ifa->ifa_name);
    }
    return UINT2NUM(ifindex);
}
#else
#define ifaddr_ifindex rb_f_notimplement
#endif

/*
 * call-seq:
 *   ifaddr.flags => integer
 *
 * Returns the flags of _ifaddr_.
 */

static VALUE
ifaddr_flags(VALUE self)
{
    rb_ifaddr_t *rifaddr = get_ifaddr(self);
    struct ifaddrs *ifa = rifaddr->ifaddr;
    return IFAFLAGS2NUM(ifa->ifa_flags);
}

/*
 * call-seq:
 *   ifaddr.addr => addrinfo
 *
 * Returns the address of _ifaddr_.
 * nil is returned if address is not available in _ifaddr_.
 */

static VALUE
ifaddr_addr(VALUE self)
{
    rb_ifaddr_t *rifaddr = get_ifaddr(self);
    struct ifaddrs *ifa = rifaddr->ifaddr;
    if (ifa->ifa_addr)
        return rsock_sockaddr_obj(ifa->ifa_addr, rsock_sockaddr_len(ifa->ifa_addr));
    return Qnil;
}

/*
 * call-seq:
 *   ifaddr.netmask => addrinfo
 *
 * Returns the netmask address of _ifaddr_.
 * nil is returned if netmask is not available in _ifaddr_.
 */

static VALUE
ifaddr_netmask(VALUE self)
{
    rb_ifaddr_t *rifaddr = get_ifaddr(self);
    struct ifaddrs *ifa = rifaddr->ifaddr;
    if (ifa->ifa_netmask)
        return rsock_sockaddr_obj(ifa->ifa_netmask, rsock_sockaddr_len(ifa->ifa_netmask));
    return Qnil;
}

/*
 * call-seq:
 *   ifaddr.broadaddr => addrinfo
 *
 * Returns the broadcast address of _ifaddr_.
 * nil is returned if the flags doesn't have IFF_BROADCAST.
 */

static VALUE
ifaddr_broadaddr(VALUE self)
{
    rb_ifaddr_t *rifaddr = get_ifaddr(self);
    struct ifaddrs *ifa = rifaddr->ifaddr;
    if ((ifa->ifa_flags & IFF_BROADCAST) && ifa->ifa_broadaddr)
        return rsock_sockaddr_obj(ifa->ifa_broadaddr, rsock_sockaddr_len(ifa->ifa_broadaddr));
    return Qnil;
}

/*
 * call-seq:
 *   ifaddr.dstaddr => addrinfo
 *
 * Returns the destination address of _ifaddr_.
 * nil is returned if the flags doesn't have IFF_POINTOPOINT.
 */

static VALUE
ifaddr_dstaddr(VALUE self)
{
    rb_ifaddr_t *rifaddr = get_ifaddr(self);
    struct ifaddrs *ifa = rifaddr->ifaddr;
    if ((ifa->ifa_flags & IFF_POINTOPOINT) && ifa->ifa_dstaddr)
        return rsock_sockaddr_obj(ifa->ifa_dstaddr, rsock_sockaddr_len(ifa->ifa_dstaddr));
    return Qnil;
}

#ifdef HAVE_STRUCT_IF_DATA_IFI_VHID
/*
 * call-seq:
 *   ifaddr.vhid => Integer
 *
 * Returns the vhid address of _ifaddr_.
 * nil is returned if there is no vhid.
 */

static VALUE
ifaddr_vhid(VALUE self)
{
    rb_ifaddr_t *rifaddr = get_ifaddr(self);
    struct ifaddrs *ifa = rifaddr->ifaddr;
    if (ifa->ifa_data)
        return (INT2FIX(((struct if_data*)ifa->ifa_data)->ifi_vhid));
    else
        return Qnil;
}
#endif

static void
ifaddr_inspect_flags(ifa_flags_t flags, VALUE result)
{
    const char *sep = " ";
#define INSPECT_BIT(bit, name) \
    if (flags & (bit)) { rb_str_catf(result, "%s" name, sep); flags &= ~(ifa_flags_t)(bit); sep = ","; }
#ifdef IFF_UP
    INSPECT_BIT(IFF_UP, "UP")
#endif
#ifdef IFF_BROADCAST
    INSPECT_BIT(IFF_BROADCAST, "BROADCAST")
#endif
#ifdef IFF_DEBUG
    INSPECT_BIT(IFF_DEBUG, "DEBUG")
#endif
#ifdef IFF_LOOPBACK
    INSPECT_BIT(IFF_LOOPBACK, "LOOPBACK")
#endif
#ifdef IFF_POINTOPOINT
    INSPECT_BIT(IFF_POINTOPOINT, "POINTOPOINT")
#endif
#ifdef IFF_RUNNING
    INSPECT_BIT(IFF_RUNNING, "RUNNING")
#endif
#ifdef IFF_NOARP
    INSPECT_BIT(IFF_NOARP, "NOARP")
#endif
#ifdef IFF_PROMISC
    INSPECT_BIT(IFF_PROMISC, "PROMISC")
#endif
#ifdef IFF_NOTRAILERS
    INSPECT_BIT(IFF_NOTRAILERS, "NOTRAILERS")
#endif
#ifdef IFF_ALLMULTI
    INSPECT_BIT(IFF_ALLMULTI, "ALLMULTI")
#endif
#ifdef IFF_SIMPLEX
    INSPECT_BIT(IFF_SIMPLEX, "SIMPLEX")
#endif
#ifdef IFF_MASTER
    INSPECT_BIT(IFF_MASTER, "MASTER")
#endif
#ifdef IFF_SLAVE
    INSPECT_BIT(IFF_SLAVE, "SLAVE")
#endif
#ifdef IFF_MULTICAST
    INSPECT_BIT(IFF_MULTICAST, "MULTICAST")
#endif
#ifdef IFF_PORTSEL
    INSPECT_BIT(IFF_PORTSEL, "PORTSEL")
#endif
#ifdef IFF_AUTOMEDIA
    INSPECT_BIT(IFF_AUTOMEDIA, "AUTOMEDIA")
#endif
#ifdef IFF_DYNAMIC
    INSPECT_BIT(IFF_DYNAMIC, "DYNAMIC")
#endif
#ifdef IFF_LOWER_UP
    INSPECT_BIT(IFF_LOWER_UP, "LOWER_UP")
#endif
#ifdef IFF_DORMANT
    INSPECT_BIT(IFF_DORMANT, "DORMANT")
#endif
#ifdef IFF_ECHO
    INSPECT_BIT(IFF_ECHO, "ECHO")
#endif
#undef INSPECT_BIT
    if (flags) {
        rb_str_catf(result, "%s%#"PRIxIFAFLAGS, sep, flags);
    }
}

/*
 * call-seq:
 *   ifaddr.inspect => string
 *
 * Returns a string to show contents of _ifaddr_.
 */

static VALUE
ifaddr_inspect(VALUE self)
{
    rb_ifaddr_t *rifaddr = get_ifaddr(self);
    struct ifaddrs *ifa;
    VALUE result;

    ifa = rifaddr->ifaddr;

    result = rb_str_new_cstr("#<");

    rb_str_append(result, rb_class_name(CLASS_OF(self)));
    rb_str_cat2(result, " ");
    rb_str_cat2(result, ifa->ifa_name);

    if (ifa->ifa_flags)
        ifaddr_inspect_flags(ifa->ifa_flags, result);

    if (ifa->ifa_addr) {
      rb_str_cat2(result, " ");
      rsock_inspect_sockaddr(ifa->ifa_addr,
          rsock_sockaddr_len(ifa->ifa_addr),
          result);
    }
    if (ifa->ifa_netmask) {
      rb_str_cat2(result, " netmask=");
      rsock_inspect_sockaddr(ifa->ifa_netmask,
          rsock_sockaddr_len(ifa->ifa_netmask),
          result);
    }

    if ((ifa->ifa_flags & IFF_BROADCAST) && ifa->ifa_broadaddr) {
      rb_str_cat2(result, " broadcast=");
      rsock_inspect_sockaddr(ifa->ifa_broadaddr,
          rsock_sockaddr_len(ifa->ifa_broadaddr),
          result);
    }

    if ((ifa->ifa_flags & IFF_POINTOPOINT) && ifa->ifa_dstaddr) {
      rb_str_cat2(result, " dstaddr=");
      rsock_inspect_sockaddr(ifa->ifa_dstaddr,
          rsock_sockaddr_len(ifa->ifa_dstaddr),
          result);
    }

    rb_str_cat2(result, ">");
    return result;
}
#endif

#ifdef HAVE_GETIFADDRS
/*
 * call-seq:
 *   Socket.getifaddrs => [ifaddr1, ...]
 *
 * Returns an array of interface addresses.
 * An element of the array is an instance of Socket::Ifaddr.
 *
 * This method can be used to find multicast-enabled interfaces:
 *
 *   pp Socket.getifaddrs.reject {|ifaddr|
 *     !ifaddr.addr.ip? || (ifaddr.flags & Socket::IFF_MULTICAST == 0)
 *   }.map {|ifaddr| [ifaddr.name, ifaddr.ifindex, ifaddr.addr] }
 *   #=> [["eth0", 2, #<Addrinfo: 221.186.184.67>],
 *   #    ["eth0", 2, #<Addrinfo: fe80::216:3eff:fe95:88bb%eth0>]]
 *
 * Example result on GNU/Linux:
 *   pp Socket.getifaddrs
 *   #=> [#<Socket::Ifaddr lo UP,LOOPBACK,RUNNING,0x10000 PACKET[protocol=0 lo hatype=772 HOST hwaddr=00:00:00:00:00:00]>,
 *   #    #<Socket::Ifaddr eth0 UP,BROADCAST,RUNNING,MULTICAST,0x10000 PACKET[protocol=0 eth0 hatype=1 HOST hwaddr=00:16:3e:95:88:bb] broadcast=PACKET[protocol=0 eth0 hatype=1 HOST hwaddr=ff:ff:ff:ff:ff:ff]>,
 *   #    #<Socket::Ifaddr sit0 NOARP PACKET[protocol=0 sit0 hatype=776 HOST hwaddr=00:00:00:00]>,
 *   #    #<Socket::Ifaddr lo UP,LOOPBACK,RUNNING,0x10000 127.0.0.1 netmask=255.0.0.0>,
 *   #    #<Socket::Ifaddr eth0 UP,BROADCAST,RUNNING,MULTICAST,0x10000 221.186.184.67 netmask=255.255.255.240 broadcast=221.186.184.79>,
 *   #    #<Socket::Ifaddr lo UP,LOOPBACK,RUNNING,0x10000 ::1 netmask=ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff>,
 *   #    #<Socket::Ifaddr eth0 UP,BROADCAST,RUNNING,MULTICAST,0x10000 fe80::216:3eff:fe95:88bb%eth0 netmask=ffff:ffff:ffff:ffff::>]
 *
 * Example result on FreeBSD:
 *   pp Socket.getifaddrs
 *   #=> [#<Socket::Ifaddr usbus0 UP,0x10000 LINK[usbus0]>,
 *   #    #<Socket::Ifaddr re0 UP,BROADCAST,RUNNING,MULTICAST,0x800 LINK[re0 3a:d0:40:9a:fe:e8]>,
 *   #    #<Socket::Ifaddr re0 UP,BROADCAST,RUNNING,MULTICAST,0x800 10.250.10.18 netmask=255.255.255.? (7 bytes for 16 bytes sockaddr_in) broadcast=10.250.10.255>,
 *   #    #<Socket::Ifaddr re0 UP,BROADCAST,RUNNING,MULTICAST,0x800 fe80:2::38d0:40ff:fe9a:fee8 netmask=ffff:ffff:ffff:ffff::>,
 *   #    #<Socket::Ifaddr re0 UP,BROADCAST,RUNNING,MULTICAST,0x800 2001:2e8:408:10::12 netmask=UNSPEC>,
 *   #    #<Socket::Ifaddr plip0 POINTOPOINT,MULTICAST,0x800 LINK[plip0]>,
 *   #    #<Socket::Ifaddr lo0 UP,LOOPBACK,RUNNING,MULTICAST LINK[lo0]>,
 *   #    #<Socket::Ifaddr lo0 UP,LOOPBACK,RUNNING,MULTICAST ::1 netmask=ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff>,
 *   #    #<Socket::Ifaddr lo0 UP,LOOPBACK,RUNNING,MULTICAST fe80:4::1 netmask=ffff:ffff:ffff:ffff::>,
 *   #    #<Socket::Ifaddr lo0 UP,LOOPBACK,RUNNING,MULTICAST 127.0.0.1 netmask=255.?.?.? (5 bytes for 16 bytes sockaddr_in)>]
 *
 */

static VALUE
socket_s_getifaddrs(VALUE self)
{
    return rsock_getifaddrs();
}
#else
#define socket_s_getifaddrs rb_f_notimplement
#endif

void
rsock_init_sockifaddr(void)
{
#ifdef HAVE_GETIFADDRS
    /*
     * Document-class: Socket::Ifaddr
     *
     * Socket::Ifaddr represents a result of getifaddrs() function.
     */
    rb_cSockIfaddr = rb_define_class_under(rb_cSocket, "Ifaddr", rb_cData);
    rb_define_method(rb_cSockIfaddr, "inspect", ifaddr_inspect, 0);
    rb_define_method(rb_cSockIfaddr, "name", ifaddr_name, 0);
    rb_define_method(rb_cSockIfaddr, "ifindex", ifaddr_ifindex, 0);
    rb_define_method(rb_cSockIfaddr, "flags", ifaddr_flags, 0);
    rb_define_method(rb_cSockIfaddr, "addr", ifaddr_addr, 0);
    rb_define_method(rb_cSockIfaddr, "netmask", ifaddr_netmask, 0);
    rb_define_method(rb_cSockIfaddr, "broadaddr", ifaddr_broadaddr, 0);
    rb_define_method(rb_cSockIfaddr, "dstaddr", ifaddr_dstaddr, 0);
#ifdef HAVE_STRUCT_IF_DATA_IFI_VHID
    rb_define_method(rb_cSockIfaddr, "vhid", ifaddr_vhid, 0);
#endif
#endif

    rb_define_singleton_method(rb_cSocket, "getifaddrs", socket_s_getifaddrs, 0);
}
