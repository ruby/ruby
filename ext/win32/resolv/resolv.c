#include <ruby.h>
#include <ruby/encoding.h>
#include <windows.h>
#include <windns.h>
#ifndef NTDDI_VERSION
#define NTDDI_VERSION 0x06000000
#endif
#include <iphlpapi.h>

#ifndef numberof
#define numberof(array) ((int)(sizeof(array) / sizeof((array)[0])))
#endif

static VALUE
w32error_make_error(DWORD e)
{
    char buffer[512], *p;
    DWORD source = 0;
    VALUE args[2];
    if (!FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM |
                       FORMAT_MESSAGE_IGNORE_INSERTS, &source, e,
                       MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_US),
                       buffer, sizeof(buffer), NULL)) {
        snprintf(buffer, sizeof(buffer), "Unknown Error %lu", (unsigned long)e);
    }
    p = buffer;
    while ((p = strpbrk(p, "\r\n")) != NULL) {
        memmove(p, p + 1, strlen(p));
        if (!p[1]) {
            p[0] = '\0';
            break;
        }
    }
    args[0] = ULONG2NUM(e);
    args[1] = rb_str_new_cstr(buffer);
    return rb_class_new_instance(2, args, rb_path2class("Win32::Resolv::Error"));
}

static void
w32error_check(DWORD e)
{
    if (e != NO_ERROR) {
        rb_exc_raise(w32error_make_error(e));
    }
}

static VALUE
wchar_to_utf8(const WCHAR *w, int n)
{
    int clen = WideCharToMultiByte(CP_UTF8, 0, w, n, NULL, 0, NULL, NULL);
    VALUE str = rb_enc_str_new(NULL, clen, rb_utf8_encoding());
    WideCharToMultiByte(CP_UTF8, 0, w, n, RSTRING_PTR(str), clen, NULL, NULL);
    return str;
}

static VALUE
get_dns_server_list(VALUE self)
{
    FIXED_INFO *fixedinfo = NULL;
    ULONG buflen = 0;
    DWORD ret;
    VALUE buf, nameservers = Qnil;

    ret = GetNetworkParams(NULL, &buflen);
    if (ret != ERROR_BUFFER_OVERFLOW) w32error_check(ret);
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
    w32error_check(ret);

    return nameservers;
}


static const WCHAR TCPIP_Params[] = L"SYSTEM\\CurrentControlSet\\Services\\Tcpip\\Parameters";

static void
hkey_finalize(void *p)
{
    RegCloseKey((HKEY)p);
}

static const rb_data_type_t hkey_type = {
    "RegKey",
    {0, hkey_finalize},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE
hkey_close(VALUE self)
{
    RegCloseKey((HKEY)DATA_PTR(self));
    DATA_PTR(self) = 0;
    return self;
}

static VALUE reg_key_class;

static VALUE
reg_open_key(VALUE klass, HKEY hkey, const WCHAR *wname)
{
    VALUE k = TypedData_Wrap_Struct(klass, &hkey_type, NULL);
    DWORD e = RegOpenKeyExW(hkey, wname, 0, KEY_READ, (HKEY *)&DATA_PTR(k));
    if (e == ERROR_FILE_NOT_FOUND) return Qnil;
    w32error_check(e);
    return rb_ensure(rb_yield, k, hkey_close, k);
}

static VALUE
tcpip_params_open(VALUE klass)
{
    return reg_open_key(reg_key_class, HKEY_LOCAL_MACHINE, TCPIP_Params);
}

static int
to_wname(VALUE *name, WCHAR *wname, int wlen)
{
    const char *n = StringValueCStr(*name);
    int nlen = RSTRING_LEN(*name);
    int len = MultiByteToWideChar(CP_UTF8, 0, n, nlen, wname, wlen - 1);
    if (len == 0) w32error_check(GetLastError());
    if (len >= wlen) rb_raise(rb_eArgError, "too long name");
    wname[len] = L'\0';
    return len;
}

static VALUE
reg_open(VALUE self, VALUE name)
{
    HKEY hkey = DATA_PTR(self);
    WCHAR wname[256];
    to_wname(&name, wname, numberof(wname));
    return reg_open_key(CLASS_OF(self), hkey, wname);
}


static VALUE
reg_each_key(VALUE self)
{
    WCHAR wname[256];
    HKEY hkey = DATA_PTR(self);
    VALUE k = TypedData_Wrap_Struct(CLASS_OF(self), &hkey_type, NULL);
    DWORD i, e, n;
    for (i = 0; n = numberof(wname), (e = RegEnumKeyExW(hkey, i, wname, &n, NULL, NULL, NULL, NULL)) == ERROR_SUCCESS; i++) {
        e = RegOpenKeyExW(hkey, wname, 0, KEY_READ, (HKEY *)&DATA_PTR(k));
        w32error_check(e);
        rb_ensure(rb_yield, k, hkey_close, k);
    }
    if (e != ERROR_NO_MORE_ITEMS) w32error_check(e);
    return self;
}

static inline DWORD
swap_dw(DWORD x)
{
#if defined(_MSC_VER)
    return _byteswap_ulong(x);
#else
    return __builtin_bswap32(x);
#endif
}

static VALUE
reg_value(VALUE self, VALUE name)
{
    HKEY hkey = DATA_PTR(self);
    DWORD type = 0, size = 0, e;
    VALUE result, value_buffer;
    void *buffer;
    WCHAR wname[256];
    to_wname(&name, wname, numberof(wname));
    e = RegGetValueW(hkey, NULL, wname, RRF_RT_ANY, &type, NULL, &size);
    if (e == ERROR_FILE_NOT_FOUND) return Qnil;
    w32error_check(e);
# define get_value_2nd(data, dsize) do { \
        DWORD type2 = type; \
        w32error_check(RegGetValueW(hkey, NULL, wname, RRF_RT_ANY, &type2, data, dsize)); \
        if (type != type2) { \
            rb_raise(rb_eRuntimeError, "registry value type changed %lu -> %lu", \
                     (unsigned long)type, (unsigned long)type2); \
        } \
    } while (0)

    switch (type) {
      case REG_DWORD: case REG_DWORD_BIG_ENDIAN:
        {
            DWORD d;
            if (size != sizeof(d)) rb_raise(rb_eRuntimeError, "invalid size returned: %lu", (unsigned long)size);
            w32error_check(RegGetValueW(hkey, NULL, wname, RRF_RT_REG_DWORD, &type, &d, &size));
            if (type == REG_DWORD_BIG_ENDIAN) d = swap_dw(d);
            return ULONG2NUM(d);
        }
      case REG_QWORD:
        {
            QWORD q;
            if (size != sizeof(q)) rb_raise(rb_eRuntimeError, "invalid size returned: %lu", (unsigned long)size);
            w32error_check(RegGetValueW(hkey, NULL, wname, RRF_RT_REG_QWORD, &type, &q, &size));
            return ULL2NUM(q);
        }
      case REG_SZ: case REG_MULTI_SZ: case REG_EXPAND_SZ:
        if (size % sizeof(WCHAR)) rb_raise(rb_eRuntimeError, "invalid size returned: %lu", (unsigned long)size);
        buffer = ALLOCV_N(char, value_buffer, size);
        get_value_2nd(buffer, &size);
        if (type == REG_MULTI_SZ) {
            const WCHAR *w = (WCHAR *)buffer;
            result = rb_ary_new();
            size /= sizeof(WCHAR);
            size -= 1;
            for (size_t i = 0; i < size; ++i) {
                int n = lstrlenW(w+i);
                rb_ary_push(result, wchar_to_utf8(w+i, n));
                i += n;
            }
        }
        else {
            result = wchar_to_utf8((WCHAR *)buffer, lstrlenW((WCHAR *)buffer));
        }
        ALLOCV_END(value_buffer);
        break;
      default:
        result = rb_str_new(0, size);
        get_value_2nd(RSTRING_PTR(result), &size);
        rb_str_set_len(result, size);
        break;
    }
    return result;
}

void
InitVM_resolv(void)
{
    VALUE mWin32 = rb_define_module("Win32");
    VALUE resolv = rb_define_module_under(mWin32, "Resolv");
    VALUE singl = rb_singleton_class(resolv);
    VALUE regkey = rb_define_class_under(resolv, "registry key", rb_cObject);

    reg_key_class = regkey;
    rb_undef_alloc_func(regkey);
    rb_define_private_method(singl, "get_dns_server_list", get_dns_server_list, 0);
    rb_define_private_method(singl, "tcpip_params", tcpip_params_open, 0);
    rb_define_method(regkey, "open", reg_open, 1);
    rb_define_method(regkey, "each_key", reg_each_key, 0);
    rb_define_method(regkey, "value", reg_value, 1);
}

void
Init_resolv(void)
{
    InitVM(resolv);
}
