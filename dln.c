/**********************************************************************

  dln.c -

  $Author$
  created at: Tue Jan 18 17:05:06 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#ifdef RUBY_EXPORT
#include "ruby/ruby.h"
#define dln_notimplement rb_notimplement
#define dln_memerror rb_memerror
#define dln_exit rb_exit
#define dln_loaderror rb_loaderror
#define dln_fatalerror rb_fatal
#else
#define dln_notimplement --->>> dln not implemented <<<---
#define dln_memerror abort
#define dln_exit exit
static void dln_loaderror(const char *format, ...);
#define dln_fatalerror dln_loaderror
#endif
#include "dln.h"
#include "internal.h"
#include "internal/compilers.h"
#include "internal/namespace.h"

#ifdef HAVE_STDLIB_H
# include <stdlib.h>
#endif

#if defined(HAVE_ALLOCA_H)
#include <alloca.h>
#endif

#ifdef HAVE_STRING_H
# include <string.h>
#else
# include <strings.h>
#endif

#if defined __APPLE__
# include <AvailabilityMacros.h>
#endif

#ifndef xmalloc
void *xmalloc();
void *xcalloc();
void *xrealloc();
#endif

#undef free
#define free(x) xfree(x)

#include <stdio.h>
#if defined(_WIN32)
#include "missing/file.h"
#endif
#include <sys/types.h>
#include <sys/stat.h>

#ifndef S_ISDIR
# define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)
#endif

#ifdef HAVE_SYS_PARAM_H
# include <sys/param.h>
#endif
#ifndef MAXPATHLEN
# define MAXPATHLEN 1024
#endif

#ifdef HAVE_UNISTD_H
# include <unistd.h>
#endif

#ifndef dln_loaderror
static void
dln_loaderror(const char *format, ...)
{
    va_list ap;
    va_start(ap, format);
    vfprintf(stderr, format, ap);
    va_end(ap);
    abort();
}
#endif

#if defined(HAVE_DLOPEN) && !defined(_AIX) && !defined(_UNICOSMP)
/* dynamic load with dlopen() */
# define USE_DLN_DLOPEN
#endif

#if defined(__hp9000s300) || ((defined(__NetBSD__) || defined(__FreeBSD__) || defined(__OpenBSD__)) && !defined(__ELF__)) || defined(NeXT)
# define EXTERNAL_PREFIX "_"
#else
# define EXTERNAL_PREFIX ""
#endif
#define FUNCNAME_PREFIX EXTERNAL_PREFIX"Init_"

#if defined __CYGWIN__ || defined DOSISH
#define isdirsep(x) ((x) == '/' || (x) == '\\')
#else
#define isdirsep(x) ((x) == '/')
#endif

#if defined(_WIN32) || defined(USE_DLN_DLOPEN)
struct string_part {
    const char *ptr;
    size_t len;
};

static struct string_part
init_funcname_len(const char *file)
{
    const char *p = file, *base, *dot = NULL;

    /* Load the file as an object one */
    for (base = p; *p; p++) { /* Find position of last '/' */
        if (*p == '.' && !dot) dot = p;
        if (isdirsep(*p)) base = p+1, dot = NULL;
    }
    /* Delete suffix if it exists */
    const size_t len = (dot ? dot : p) - base;
    return (struct string_part){base, len};
}

static inline char *
concat_funcname(char *buf, const char *prefix, size_t plen, const struct string_part base)
{
    if (!buf) {
        dln_memerror();
    }
    memcpy(buf, prefix, plen);
    memcpy(buf + plen, base.ptr, base.len);
    buf[plen + base.len] = '\0';
    return buf;
}

#define build_funcname(prefix, buf, file) do {\
    const struct string_part f = init_funcname_len(file);\
    const size_t plen = sizeof(prefix "") - 1;\
    *(buf) = concat_funcname(ALLOCA_N(char, plen+f.len+1), prefix, plen, f);\
} while (0)

#define init_funcname(buf, file) build_funcname(FUNCNAME_PREFIX, buf, file)
#endif

#ifdef USE_DLN_DLOPEN
# include <dlfcn.h>
#endif

#if defined(_AIX)
#include <ctype.h>	/* for isdigit()	*/
#include <errno.h>	/* for global errno	*/
#include <sys/ldr.h>
#endif

#ifdef NeXT
#if NS_TARGET_MAJOR < 4
#include <mach-o/rld.h>
#else
#include <mach-o/dyld.h>
#ifndef NSLINKMODULE_OPTION_BINDNOW
#define NSLINKMODULE_OPTION_BINDNOW 1
#endif
#endif
#endif

#ifdef _WIN32
#include <windows.h>
#include <imagehlp.h>
#endif

#ifdef _WIN32
static const char *
dln_strerror(char *message, size_t size)
{
    int error = GetLastError();
    char *p = message;
    size_t len = snprintf(message, size, "%d: ", error);

#define format_message(sublang) FormatMessage(\
        FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,	\
        NULL, error, MAKELANGID(LANG_NEUTRAL, (sublang)),		\
        message + len, size - len, NULL)
    if (format_message(SUBLANG_ENGLISH_US) == 0)
        format_message(SUBLANG_DEFAULT);
    for (p = message + len; *p; p++) {
        if (*p == '\n' || *p == '\r')
            *p = ' ';
    }
    return message;
}
#define dln_strerror() dln_strerror(message, sizeof message)
#elif defined USE_DLN_DLOPEN
static const char *
dln_strerror(void)
{
    return (char*)dlerror();
}
#endif

#if defined(_AIX)
static void
aix_loaderror(const char *pathname)
{
    char *message[1024], errbuf[1024];
    int i;
#define ERRBUF_APPEND(s) strlcat(errbuf, (s), sizeof(errbuf))
    snprintf(errbuf, sizeof(errbuf), "load failed - %s. ", pathname);

    if (loadquery(L_GETMESSAGES, &message[0], sizeof(message)) != -1) {
        ERRBUF_APPEND("Please issue below command for detailed reasons:\n\t");
        ERRBUF_APPEND("/usr/sbin/execerror ruby ");
        for (i=0; message[i]; i++) {
            ERRBUF_APPEND("\"");
            ERRBUF_APPEND(message[i]);
            ERRBUF_APPEND("\" ");
        }
        ERRBUF_APPEND("\n");
    }
    else {
        ERRBUF_APPEND(strerror(errno));
        ERRBUF_APPEND("[loadquery failed]");
    }
    dln_loaderror("%s", errbuf);
}
#endif

#if defined _WIN32 && defined RUBY_EXPORT
HANDLE rb_libruby_handle(void);

static int
rb_w32_check_imported(HMODULE ext, HMODULE mine)
{
    ULONG size;
    const IMAGE_IMPORT_DESCRIPTOR *desc;

    desc = ImageDirectoryEntryToData(ext, TRUE, IMAGE_DIRECTORY_ENTRY_IMPORT, &size);
    if (!desc) return 0;
    while (desc->Name) {
        PIMAGE_THUNK_DATA pint = (PIMAGE_THUNK_DATA)((char *)ext + desc->Characteristics);
        PIMAGE_THUNK_DATA piat = (PIMAGE_THUNK_DATA)((char *)ext + desc->FirstThunk);
        for (; piat->u1.Function; piat++, pint++) {
            static const char prefix[] = "rb_";
            PIMAGE_IMPORT_BY_NAME pii;
            const char *name;

            if (IMAGE_SNAP_BY_ORDINAL(pint->u1.Ordinal)) continue;
            pii = (PIMAGE_IMPORT_BY_NAME)((char *)ext + (size_t)pint->u1.AddressOfData);
            name = (const char *)pii->Name;
            if (strncmp(name, prefix, sizeof(prefix) - 1) == 0) {
                FARPROC addr = GetProcAddress(mine, name);
                if (addr) return (FARPROC)piat->u1.Function == addr;
            }
        }
        desc++;
    }
    return 1;
}
#endif

#if defined(DLN_NEEDS_ALT_SEPARATOR) && DLN_NEEDS_ALT_SEPARATOR
#define translit_separator(src) do { \
        char *tmp = ALLOCA_N(char, strlen(src) + 1), *p = tmp, c; \
        do { \
            *p++ = ((c = *file++) == '/') ? DLN_NEEDS_ALT_SEPARATOR : c; \
        } while (c); \
        (src) = tmp; \
    } while (0)
#else
#define translit_separator(str) (void)(str)
#endif

#ifdef USE_DLN_DLOPEN
# include "ruby/internal/stdbool.h"
# include "internal/warnings.h"
static bool
dln_incompatible_func(void *handle, const char *funcname, void *const fp, const char **libname)
{
    void *ex = dlsym(handle, funcname);
    if (!ex) return false;
    if (ex == fp) return false;
#  if defined(HAVE_DLADDR) && !defined(__CYGWIN__)
    Dl_info dli;
    if (dladdr(ex, &dli)) {
        *libname = dli.dli_fname;
    }
#  endif
    return true;
}

COMPILER_WARNING_PUSH
#if defined(__clang__) || GCC_VERSION_SINCE(4, 2, 0)
COMPILER_WARNING_IGNORED(-Wpedantic)
#endif
static bool
dln_incompatible_library_p(void *handle, const char **libname)
{
#define check_func(func) \
    if (dln_incompatible_func(handle, EXTERNAL_PREFIX #func, (void *)&func, libname)) \
        return true
    check_func(ruby_xmalloc);
    return false;
}
COMPILER_WARNING_POP
#endif

#if !defined(MAC_OS_X_VERSION_MIN_REQUIRED)
/* assume others than old Mac OS X have no problem */
# define dln_disable_dlclose() false

#elif !defined(MAC_OS_X_VERSION_10_11) || \
    (MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_11)
/* targeting older versions only */
# define dln_disable_dlclose() true

#elif MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_11
/* targeting newer versions only */
# define dln_disable_dlclose() false

#else
/* support both versions, and check at runtime */
# include <sys/sysctl.h>

static bool
dln_disable_dlclose(void)
{
    int mib[] = {CTL_KERN, KERN_OSREV};
    int32_t rev;
    size_t size = sizeof(rev);
    if (sysctl(mib, numberof(mib), &rev, &size, NULL, 0)) return true;
    if (rev < MAC_OS_X_VERSION_10_11) return true;
    return false;
}
#endif

#if defined(_WIN32) || defined(USE_DLN_DLOPEN)
static void *
dln_open(const char *file)
{
    static const char incompatible[] = "incompatible library version";
    const char *error = NULL;
    void *handle;

#if defined(_WIN32)
    char message[1024];

    /* Convert the file path to wide char */
    WCHAR *winfile = rb_w32_mbstr_to_wstr(CP_UTF8, file, -1, NULL);
    if (!winfile) {
        dln_memerror();
    }

    /* Load file */
    handle = LoadLibraryW(winfile);
    free(winfile);

    if (!handle) {
        error = dln_strerror();
        goto failed;
    }

# if defined(RUBY_EXPORT)
    if (!rb_w32_check_imported(handle, rb_libruby_handle())) {
        FreeLibrary(handle);
        error = incompatible;
        goto failed;
    }
# endif

#elif defined(USE_DLN_DLOPEN)

# ifndef RTLD_LAZY
#  define RTLD_LAZY 1
# endif
# ifdef __INTERIX
#  undef RTLD_GLOBAL
# endif
# ifndef RTLD_GLOBAL
#  define RTLD_GLOBAL 0
# endif
# ifndef RTLD_LOCAL
#  define RTLD_LOCAL 0 /* TODO: 0??? some systems (including libc) use 0x00100 for RTLD_GLOBAL, 0x00000 for RTLD_LOCAL */
# endif

    /* Load file */
    int mode = rb_namespace_available() ? RTLD_LAZY|RTLD_LOCAL : RTLD_LAZY|RTLD_GLOBAL;
    handle = dlopen(file, mode);
    if (handle == NULL) {
        error = dln_strerror();
        goto failed;
    }

# if defined(RUBY_EXPORT)
    {
        const char *libruby_name = NULL;
        if (dln_incompatible_library_p(handle, &libruby_name)) {
            if (dln_disable_dlclose()) {
                /* dlclose() segfaults */
                if (libruby_name) {
                    dln_fatalerror("linked to incompatible %s - %s", libruby_name, file);
                }
                dln_fatalerror("%s - %s", incompatible, file);
            }
            else {
                if (libruby_name) {
                    const size_t len = strlen(libruby_name);
                    char *const tmp = ALLOCA_N(char, len + 1);
                    if (tmp) memcpy(tmp, libruby_name, len + 1);
                    libruby_name = tmp;
                }
                dlclose(handle);
                if (libruby_name) {
                    dln_loaderror("linked to incompatible %s - %s", libruby_name, file);
                }
                error = incompatible;
                goto failed;
            }
        }
    }
# endif
#endif

    return handle;

  failed:
    dln_loaderror("%s - %s", error, file);
}

static void *
dln_sym(void *handle, const char *symbol)
{
#if defined(_WIN32)
    return GetProcAddress(handle, symbol);
#elif defined(USE_DLN_DLOPEN)
    return dlsym(handle, symbol);
#endif
}

static uintptr_t
dln_sym_func(void *handle, const char *symbol)
{
    void *func = dln_sym(handle, symbol);

    if (func == NULL) {
        const char *error;
#if defined(_WIN32)
        char message[1024];
        error = dln_strerror();
#elif defined(USE_DLN_DLOPEN)
        const size_t errlen = strlen(error = dln_strerror()) + 1;
        error = memcpy(ALLOCA_N(char, errlen), error, errlen);
#endif
        dln_loaderror("%s - %s", error, symbol);
    }
    return (uintptr_t)func;
}

#define dln_sym_callable(rettype, argtype, handle, symbol) \
    (*(rettype (*)argtype)dln_sym_func(handle, symbol))
#endif

void *
dln_symbol(void *handle, const char *symbol)
{
#if defined(_WIN32) || defined(USE_DLN_DLOPEN)
    if (EXTERNAL_PREFIX[0]) {
        const size_t symlen = strlen(symbol);
        char *const tmp = ALLOCA_N(char, symlen + sizeof(EXTERNAL_PREFIX));
        if (!tmp) dln_memerror();
        memcpy(tmp, EXTERNAL_PREFIX, sizeof(EXTERNAL_PREFIX) - 1);
        memcpy(tmp + sizeof(EXTERNAL_PREFIX) - 1, symbol, symlen + 1);
        symbol = tmp;
    }
    if (handle == NULL) {
# if defined(USE_DLN_DLOPEN)
        handle = dlopen(NULL, RTLD_LAZY | RTLD_GLOBAL);
# elif defined(_WIN32)
        handle = rb_libruby_handle();
# else
        return NULL;
# endif
    }
    return dln_sym(handle, symbol);
#else
    return NULL;
#endif
}


#if defined(RUBY_DLN_CHECK_ABI) && defined(USE_DLN_DLOPEN)
static bool
abi_check_enabled_p(void)
{
    const char *val = getenv("RUBY_ABI_CHECK");
    return val == NULL || !(val[0] == '0' && val[1] == '\0');
}
#endif

static void *
dln_load_and_init(const char *file, const char *init_fct_name)
{
#if defined(_WIN32) || defined(USE_DLN_DLOPEN)
    void *handle = dln_open(file);

#ifdef RUBY_DLN_CHECK_ABI
    typedef unsigned long long abi_version_number;
    abi_version_number binary_abi_version =
        dln_sym_callable(abi_version_number, (void), handle, EXTERNAL_PREFIX "ruby_abi_version")();
    if (binary_abi_version != RUBY_ABI_VERSION && abi_check_enabled_p()) {
        dln_loaderror("incompatible ABI version of binary - %s", file);
    }
#endif

    /* Call the init code */
    dln_sym_callable(void, (void), handle, init_fct_name)();

    return handle;

#elif defined(_AIX)
    {
        void (*init_fct)(void);

        /* TODO: check - AIX's load system call will return the first/last symbol/function? */
        init_fct = (void(*)(void))load((char*)file, 1, 0);
        if (init_fct == NULL) {
            aix_loaderror(file);
        }
        if (loadbind(0, (void*)dln_load, (void*)init_fct) == -1) {
            aix_loaderror(file);
        }
        (*init_fct)();
        return (void*)init_fct;
    }
#else
    dln_notimplement();
#endif

    return 0;			/* dummy return */
}

void *
dln_load(const char *file)
{
#if defined(_WIN32) || defined(USE_DLN_DLOPEN)
    char *init_fct_name;
    init_funcname(&init_fct_name, file);
    return dln_load_and_init(file, init_fct_name);
#else
    dln_notimplement();
    return 0;
#endif
}

void *
dln_load_feature(const char *file, const char *fname)
{
#if defined(_WIN32) || defined(USE_DLN_DLOPEN)
    char *init_fct_name;
    init_funcname(&init_fct_name, fname);
    return dln_load_and_init(file, init_fct_name);
#else
    dln_notimplement();
    return 0;
#endif
}
