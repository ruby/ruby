#include <ruby.h>
#include <ruby/encoding.h>
#include <windows.h>
#ifndef NTDDI_VERSION
#define NTDDI_VERSION 0x06000000
#endif
#include <iphlpapi.h>

static VALUE
w32error_make_error(DWORD e)
{
    VALUE code = ULONG2NUM(e);
    return rb_class_new_instance(1, &code, rb_path2class("Win32::Resolv::Error"));
}

NORETURN(static void w32error_raise(DWORD e));

static void
w32error_raise(DWORD e)
{
    rb_exc_raise(w32error_make_error(e));
}

static VALUE
get_dns_server_list(VALUE self)
{
    FIXED_INFO *fixedinfo = NULL;
    ULONG buflen = 0;
    DWORD ret;
    VALUE buf, nameservers = Qnil;

    ret = GetNetworkParams(NULL, &buflen);
    if (ret != NO_ERROR && ret != ERROR_BUFFER_OVERFLOW) {
        w32error_raise(ret);
    }
    fixedinfo = ALLOCV(buf, buflen);
    ret = GetNetworkParams(fixedinfo, &buflen);
    if (ret == NO_ERROR) {
        const IP_ADDR_STRING *ipaddr = &fixedinfo->DnsServerList;
        nameservers = rb_ary_new();
        do {
            const char *s = ipaddr->IpAddress.String;
            if (!*s) continue;
            if (strcmp(s, "0.0.0.0") == 0) continue;
            rb_ary_push(nameservers, rb_str_new_cstr(s));
        } while ((ipaddr = ipaddr->Next) != NULL);
    }
    ALLOCV_END(buf);
    if (ret != NO_ERROR) w32error_raise(ret);

    return nameservers;
}

void
InitVM_resolv(void)
{
    VALUE mWin32 = rb_define_module("Win32");
    VALUE resolv = rb_define_module_under(mWin32, "Resolv");
    VALUE singl = rb_singleton_class(resolv);
    rb_define_private_method(singl, "get_dns_server_list", get_dns_server_list, 0);
}

void
Init_resolv(void)
{
    InitVM(resolv);
}
