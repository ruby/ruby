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
OS = mswin32
BANG = !
APPEND = echo.>>$(MAKEFILE)
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
i386-$(OS): -prologue- -i386- -epilogue-
i486-$(OS): -prologue- -i486- -epilogue-
i586-$(OS): -prologue- -i586- -epilogue-
i686-$(OS): -prologue- -i686- -epilogue-
alpha-$(OS): -prologue- -alpha- -epilogue-

-prologue-: -basic-vars- -system-vars- -version- -program-name-

-basic-vars-: nul
	@type << > $(MAKEFILE)
### Makefile for ruby $(OS) ###
MAKE = nmake
srcdir = $(srcdir:\=/)
prefix = $(prefix:\=/)
EXTSTATIC = $(EXTSTATIC)
!if defined(USE_WINSOCK2)
USE_WINSOCK2 = $(USE_WINSOCK2)
!endif
!if defined(RDOCTARGET)
RDOCTARGET = $(RDOCTARGET)
!endif
!if defined(EXTOUT)
EXTOUT = $(EXTOUT)
!endif
<<

-system-vars-: -osname- -runtime-

-osname-: nul
	@echo OS = mswin32 >>$(MAKEFILE)

-runtime-: nul
	@$(CC) -MD <<rtname.c user32.lib -link > nul
#include <windows.h>
#include <memory.h>
#include <string.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
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
    else ver = "60";
    printf("RT = %s\n", base);
    printf("RT_VER = %s\n", ver);
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
	@$(APPEND)
	@$(CPP) -I$(srcdir) <<"Creating $(MAKEFILE)" | findstr "=" >>$(MAKEFILE)
#define RUBY_REVISION 0
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
	@echo $(ARCH) = alpha>>$(MAKEFILE)
-ix86-: nul
	@echo $(ARCH) = x86>>$(MAKEFILE)

-i386-: -ix86-
	@echo $(CPU) = 3>>$(MAKEFILE)
-i486-: -ix86-
	@echo $(CPU) = 4>>$(MAKEFILE)
-i586-: -ix86-
	@echo $(CPU) = 5>>$(MAKEFILE)
-i686-: -ix86-
	@echo $(CPU) = 6>>$(MAKEFILE)

-epilogue-: nul
!if exist(confargs.c)
	@$(APPEND)
	@$(CPP) confargs.c 2>&1 | findstr "! =" >> $(MAKEFILE)
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
