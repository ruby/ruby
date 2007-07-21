# -*- makefile -*-

!if "$(srcdir)" != ""
WIN32DIR = $(srcdir)/win32
!elseif "$(WIN32DIR)" == "win32"
srcdir = .
!elseif "$(WIN32DIR)" == "$(WIN32DIR:/win32=)/win32"
srcdir = $(WIN32DIR:/win32=)
!else
srcdir = $(WIN32DIR)/..
!endif
!ifndef prefix
prefix = /usr
!endif
!if "$(OS)" != "mswin64"
OS = mswin32
!endif
BANG = !
APPEND = echo>>$(MAKEFILE)
!ifdef MAKEFILE
MAKE = $(MAKE) -f $(MAKEFILE)
!else
MAKEFILE = Makefile
!endif
ARCH = PROCESSOR_ARCHITECTURE
CPU = PROCESSOR_LEVEL
CC = cl -nologo
CPP = $(CC) -EP

all: -prologue- -generic- -epilogue-
i386-mswin32: -prologue- -i386- -epilogue-
i486-mswin32: -prologue- -i486- -epilogue-
i586-mswin32: -prologue- -i586- -epilogue-
i686-mswin32: -prologue- -i686- -epilogue-
alpha-mswin32: -prologue- -alpha- -epilogue-
x64-mswin64: -prologue64- -x64- -epilogue-
ia64-mswin64: -prologue64- -ia64- -epilogue-

-prologue-: -basic-vars- -system-vars- -version- -program-name-

-prologue64-: -basic-vars- -system-vars64- -version- -program-name-

-basic-vars-: nul
	@type << > $(MAKEFILE)
### Makefile for ruby $(OS) ###
MAKE = nmake
srcdir = $(srcdir:\=/)
prefix = $(prefix:\=/)
EXTSTATIC = $(EXTSTATIC)
!if defined(RDOCTARGET)
RDOCTARGET = $(RDOCTARGET)
!endif
!if defined(EXTOUT)
EXTOUT = $(EXTOUT)
!endif
!if defined(BASERUBY)
BASERUBY = $(BASERUBY)
!endif
<<

-system-vars-: -osname- -runtime-

-system-vars64-: -osname64- -runtime-

-osname-: nul
	@echo OS = mswin32 >>$(MAKEFILE)

-osname64-: nul
	@echo OS = mswin64 >>$(MAKEFILE)

-runtime-: nul
	@$(CC) -MD <<rtname.c user32.lib > nul
#include <windows.h>
#include <memory.h>
#include <string.h>
#include <stddef.h>
#include <stdio.h>
#ifndef MAXPATHLEN
# define MAXPATHLEN 1024
#endif

int
runtime_name()
{
    char libpath[MAXPATHLEN+1];
    char *p, *base = NULL, *ver = NULL;
    HMODULE msvcrt = NULL;
    MEMORY_BASIC_INFORMATION m;

    memset(&m, 0, sizeof(m));
    if (VirtualQuery(stdin, &m, sizeof(m)) && m.State == MEM_COMMIT)
	msvcrt = (HMODULE)m.AllocationBase;
    GetModuleFileName(msvcrt, libpath, sizeof libpath);

    libpath[sizeof(libpath) - 1] = '\0';
    for (p = libpath; *p; p = CharNext(p)) {
	if (*p == '\\') {
	    base = ++p;
	}
    }
    if (!base) return 0;
    if (p = strchr(base, '.')) *p = '\0';
    for (p = base; *p; p = CharNext(p)) {
	if (!isascii(*p)) continue;
	if (isupper(*p)) {
	    *p = tolower(*p);
	}
	if (!isdigit(*p)) {
	    ver = NULL;
	} else if (!ver) {
	    ver = p;
	}
    }
    if (ver) printf("OS = $$(OS)_%s\n", ver);
    printf("RT = %s\n", base);
    return 1;
}

int main(int argc, char **argv)
{
    if (!runtime_name()) return EXIT_FAILURE;
    return EXIT_SUCCESS;
}
<<
	@.\rtname >>$(MAKEFILE)
	@del rtname.*

-version-: nul
	@$(CPP) -I$(srcdir) <<"Creating $(MAKEFILE)" >>$(MAKEFILE)
#include "version.h"
MAJOR = RUBY_VERSION_MAJOR
MINOR = RUBY_VERSION_MINOR
TEENY = RUBY_VERSION_TEENY
MSC_VER = _MSC_VER
<<

-program-name-:
	@type << >>$(MAKEFILE)
!ifdef RUBY_SUFFIX
RUBY_SUFFIX = $(RUBY_SUFFIX)
!endif
!ifdef RUBY_INSTALL_NAME
RUBY_INSTALL_NAME = $(RUBY_INSTALL_NAME)
!endif
!ifdef RUBY_SO_NAME
RUBY_SO_NAME = $(RUBY_SO_NAME)
!endif
<<

-generic-: nul
!if defined($(ARCH)) || defined($(CPU))
	@type << >>$(MAKEFILE)
!if defined($(ARCH))
$(ARCH) = $(PROCESSOR_ARCHITECTURE)
!endif
!if defined($(CPU))
$(CPU) = $(PROCESSOR_LEVEL)
!endif

<<
!endif

-alpha-: nul
	@$(APPEND) $(ARCH) = alpha
-x64-: nul
	@$(APPEND) $(ARCH) = x64
-ia64-: nul
	@$(APPEND) $(ARCH) = ia64
-ix86-: nul
	@$(APPEND) $(ARCH) = x86

-i386-: -ix86-
	@$(APPEND) $(CPU) = 3
-i486-: -ix86-
	@$(APPEND) $(CPU) = 4
-i586-: -ix86-
	@$(APPEND) $(CPU) = 5
-i686-: -ix86-
	@$(APPEND) $(CPU) = 6

-epilogue-: nul
!if exist(confargs.c)
	@$(CPP) confargs.c >> $(MAKEFILE)
	@del confargs.c
!endif
	@type << >>$(MAKEFILE)

# OS = $(OS)
# RUBY_INSTALL_NAME = ruby
# RUBY_SO_NAME = $$(RT)-$$(RUBY_INSTALL_NAME)$$(MAJOR)$$(MINOR)
# CFLAGS = -nologo -MD $$(DEBUGFLAGS) $$(OPTFLAGS) $$(PROCESSOR_FLAG)
# CPPFLAGS = -I. -I$$(srcdir) -I$$(srcdir)/missing -DLIBRUBY_SO=\"$$(LIBRUBY_SO)\"
# STACK = 0x2000000
# LDFLAGS = $$(CFLAGS) -Fm
# XLDFLAGS = 
# RFLAGS = -r
# EXTLIBS =

$(BANG)include $$(srcdir)/win32/Makefile.sub
<<
	@$(COMSPEC) /C $(srcdir:/=\)\win32\rm.bat config.h config.status
	@echo type `$(MAKE)' to make ruby for $(OS).
