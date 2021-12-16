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
#else
#define dln_notimplement --->>> dln not implemented <<<---
#define dln_memerror abort
#define dln_exit exit
static void dln_loaderror(const char *format, ...);
#endif
#include "dln.h"
#include "internal.h"
#include "internal/compilers.h"

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
#   define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)
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

#ifndef _WIN32
char *getenv();
#endif

#ifdef __APPLE__
# if defined(HAVE_DLOPEN)
   /* Mac OS X with dlopen (10.3 or later) */
#  define MACOSX_DLOPEN
# else
#  define MACOSX_DYLD
# endif
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

#if defined(HAVE_DLOPEN) && !defined(_AIX) && !defined(MACOSX_DYLD) && !defined(_UNICOSMP)
/* dynamic load with dlopen() */
# define USE_DLN_DLOPEN
#endif

#if defined(__hp9000s300) || ((defined(__NetBSD__) || defined(__FreeBSD__) || defined(__OpenBSD__)) && !defined(__ELF__)) || defined(NeXT) || defined(MACOSX_DYLD)
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

static size_t
init_funcname_len(const char **file)
{
    const char *p = *file, *base, *dot = NULL;

    /* Load the file as an object one */
    for (base = p; *p; p++) { /* Find position of last '/' */
	if (*p == '.' && !dot) dot = p;
	if (isdirsep(*p)) base = p+1, dot = NULL;
    }
    *file = base;
    /* Delete suffix if it exists */
    return (dot ? dot : p) - base;
}

static const char funcname_prefix[sizeof(FUNCNAME_PREFIX) - 1] = FUNCNAME_PREFIX;

#define init_funcname(buf, file) do {\
    const char *base = (file);\
    const size_t flen = init_funcname_len(&base);\
    const size_t plen = sizeof(funcname_prefix);\
    char *const tmp = ALLOCA_N(char, plen+flen+1);\
    if (!tmp) {\
	dln_memerror();\
    }\
    memcpy(tmp, funcname_prefix, plen);\
    memcpy(tmp+plen, base, flen);\
    tmp[plen+flen] = '\0';\
    *(buf) = tmp;\
} while (0)

#ifdef USE_DLN_DLOPEN
# include <dlfcn.h>
#endif

#ifdef __hpux
#include <errno.h>
#include "dl.h"
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
#else
#ifdef MACOSX_DYLD
#include <mach-o/dyld.h>
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
COMPILER_WARNING_PUSH
#if defined(__clang__) || GCC_VERSION_SINCE(4, 2, 0)
COMPILER_WARNING_IGNORED(-Wpedantic)
#endif
static bool
dln_incompatible_library_p(void *handle)
{
    void *ex = dlsym(handle, EXTERNAL_PREFIX"ruby_xmalloc");
    void *const fp = (void *)ruby_xmalloc;
    return ex && ex != fp;
}
COMPILER_WARNING_POP
#endif

void*
dln_load(const char *file)
{
#if (defined _WIN32 || defined USE_DLN_DLOPEN) && defined RUBY_EXPORT
    static const char incompatible[] = "incompatible library version";
#endif
#if defined _WIN32 || defined USE_DLN_DLOPEN
    const char *error = 0;
#endif

#if defined _WIN32
    HINSTANCE handle;
    WCHAR *winfile;
    char message[1024];
    void (*init_fct)(void);
    char *buf;

    /* Load the file as an object one */
    init_funcname(&buf, file);

    /* Convert the file path to wide char */
    winfile = rb_w32_mbstr_to_wstr(CP_UTF8, file, -1, NULL);
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

#if defined _WIN32 && defined RUBY_EXPORT
    if (!rb_w32_check_imported(handle, rb_libruby_handle())) {
	FreeLibrary(handle);
	error = incompatible;
	goto failed;
    }
#endif

    if ((init_fct = (void(*)(void))GetProcAddress(handle, buf)) == NULL) {
	dln_loaderror("%s - %s\n%s", dln_strerror(), buf, file);
    }

    /* Call the init code */
    (*init_fct)();
    return handle;
#else
    char *buf;
    /* Load the file as an object one */
    init_funcname(&buf, file);
    translit_separator(file);

#ifdef USE_DLN_DLOPEN
#define DLN_DEFINED
    {
	void *handle;
	void (*init_fct)(void);

#ifndef RTLD_LAZY
# define RTLD_LAZY 1
#endif
#ifdef __INTERIX
# undef RTLD_GLOBAL
#endif
#ifndef RTLD_GLOBAL
# define RTLD_GLOBAL 0
#endif

	/* Load file */
	if ((handle = (void*)dlopen(file, RTLD_LAZY|RTLD_GLOBAL)) == NULL) {
	    error = dln_strerror();
	    goto failed;
	}
# if defined RUBY_EXPORT
	{
	    if (dln_incompatible_library_p(handle)) {

#   if defined __APPLE__ && \
    defined(MAC_OS_X_VERSION_MIN_REQUIRED) && \
    (MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_11)
		/* dlclose() segfaults */
		rb_fatal("%s - %s", incompatible, file);
#   else
		dlclose(handle);
		error = incompatible;
		goto failed;
#   endif
	    }
	}
# endif

	init_fct = (void(*)(void))(VALUE)dlsym(handle, buf);
	if (init_fct == NULL) {
	    const size_t errlen = strlen(error = dln_strerror()) + 1;
	    error = memcpy(ALLOCA_N(char, errlen), error, errlen);
	    dlclose(handle);
	    goto failed;
	}
	/* Call the init code */
	(*init_fct)();

	return handle;
    }
#endif /* USE_DLN_DLOPEN */

#ifdef __hpux
#define DLN_DEFINED
    {
	shl_t lib = NULL;
	int flags;
	void (*init_fct)(void);

	flags = BIND_DEFERRED;
	lib = shl_load(file, flags, 0);
	if (lib == NULL) {
	    extern int errno;
	    dln_loaderror("%s - %s", strerror(errno), file);
	}
	shl_findsym(&lib, buf, TYPE_PROCEDURE, (void*)&init_fct);
	if (init_fct == NULL) {
	    shl_findsym(&lib, buf, TYPE_UNDEFINED, (void*)&init_fct);
	    if (init_fct == NULL) {
		errno = ENOSYM;
		dln_loaderror("%s - %s", strerror(ENOSYM), file);
	    }
	}
	(*init_fct)();
	return (void*)lib;
    }
#endif /* hpux */

#if defined(_AIX)
#define DLN_DEFINED
    {
	void (*init_fct)(void);

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
#endif /* _AIX */

#if defined(MACOSX_DYLD)
#define DLN_DEFINED
/*----------------------------------------------------
   By SHIROYAMA Takayuki Psi@fortune.nest.or.jp

   Special Thanks...
    Yu tomoak-i@is.aist-nara.ac.jp,
    Mi hisho@tasihara.nest.or.jp,
    sunshine@sunshineco.com,
    and... Miss ARAI Akino(^^;)
 ----------------------------------------------------*/
    {
	int dyld_result;
	NSObjectFileImage obj_file; /* handle, but not use it */
	/* "file" is module file name .
	   "buf" is pointer to initial function name with "_" . */

	void (*init_fct)(void);


	dyld_result = NSCreateObjectFileImageFromFile(file, &obj_file);

	if (dyld_result != NSObjectFileImageSuccess) {
	    dln_loaderror("Failed to load %.200s", file);
	}

	NSLinkModule(obj_file, file, NSLINKMODULE_OPTION_BINDNOW);

	/* lookup the initial function */
	if (!NSIsSymbolNameDefined(buf)) {
	    dln_loaderror("Failed to lookup Init function %.200s",file);
	}
	init_fct = NSAddressOfSymbol(NSLookupAndBindSymbol(buf));
	(*init_fct)();

	return (void*)init_fct;
    }
#endif

#ifndef DLN_DEFINED
    dln_notimplement();
#endif

#endif
#if defined(_WIN32) || defined(USE_DLN_DLOPEN)
  failed:
    dln_loaderror("%s - %s", error, file);
#endif

    return 0;			/* dummy return */
}
