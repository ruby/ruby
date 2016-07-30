#include <ruby.h>
#include <ruby/encoding.h>
#include <iphlpapi.h>

VALUE rb_w32_conv_from_wchar(const WCHAR *wstr, rb_encoding *enc);

static VALUE (*message_free)(VALUE);

static VALUE
locale_from_wchar(VALUE arg)
{
    return rb_w32_conv_from_wchar((WCHAR *)arg, rb_locale_encoding());
}

static VALUE
heap_free(VALUE arg)
{
    HeapFree(GetProcessHeap(), 0, (void *)arg);
    return 0;
}

static VALUE
local_free(VALUE arg)
{
    LocalFree((void *)arg);
    return 0;
}

static DWORD
delete_cr(WCHAR *buff, DWORD len)
{
    DWORD i, i0, j;
    if (!len) return 0;
    for (j = i0 = i = 0; i < len; ++i) {
	if (buff[i] != L'\r') continue;
	if (i0 > j) memcpy(&buff[j], &buff[i0], (i - i0) * sizeof(WCHAR));
	j += i - i0;
	i0 = i + 1;
    }
    if (i0 > j) memcpy(&buff[j], &buff[i0], (i - i0) * sizeof(WCHAR));
    j += i - i0;
    buff[j] = L'\0';
    return j;
}

static VALUE
w32error_init(VALUE self, VALUE code)
{
    WCHAR *buff = 0;
    DWORD len;
    VALUE str = Qnil;
    const DWORD flags =
	FORMAT_MESSAGE_FROM_SYSTEM |
	FORMAT_MESSAGE_IGNORE_INSERTS |
	FORMAT_MESSAGE_ALLOCATE_BUFFER;
    const DWORD lang = MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_US);

    rb_ivar_set(self, rb_intern("@code"), code);
    if ((len = FormatMessageW(flags, NULL, NUM2LONG(code), lang,
			      (LPWSTR)&buff, 128, NULL)) > 0) {
	const VALUE arg = (VALUE)buff;
	len = delete_cr(buff, len);
	if (len > 0 && buff[len-1] == L'\n') buff[--len] = L'\0';
	str = rb_ensure(locale_from_wchar, arg, message_free, arg);
    }
    return rb_call_super(1, &str);
}

static VALUE
w32error_make_error(DWORD e)
{
    VALUE code = ULONG2NUM(e);
    return rb_class_new_instance(1, &code, rb_path2class("Win32::Error"));
}

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
    VALUE eclass = rb_define_class_under(mWin32, "Error", rb_eStandardError);
    rb_define_method(eclass, "initialize", w32error_init, 1);
    rb_define_private_method(singl, "get_dns_server_list", get_dns_server_list, 0);
}

void
Init_resolv(void)
{
    message_free = (rb_w32_osver() >= 10) ? heap_free : local_free;
    InitVM(resolv);
}
