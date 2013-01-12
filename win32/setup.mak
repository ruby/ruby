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
i386-mswin32: -prologue32- -i386- -epilogue-
i486-mswin32: -prologue32- -i486- -epilogue-
i586-mswin32: -prologue32- -i586- -epilogue-
i686-mswin32: -prologue32- -i686- -epilogue-
alpha-mswin32: -prologue32- -alpha- -epilogue-
x64-mswin64: -prologue64- -x64- -epilogue-
ia64-mswin64: -prologue64- -ia64- -epilogue-

-prologue-: -basic-vars- -system-vars- -version- -program-name-

-prologue32-: -basic-vars- -system-vars32- -version- -program-name-

-prologue64-: -basic-vars- -system-vars64- -version- -program-name-

-basic-vars-: nul
	@type << > $(MAKEFILE)
### Makefile for ruby $(TARGET_OS) ###
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
BASERUBY = $(BASERUBY:/=\)
!endif
!if defined(NTVER)
NTVER = $(NTVER)
!endif
!if defined(USE_RUBYGEMS)
USE_RUBYGEMS = $(USE_RUBYGEMS)
!endif

<<
!if !defined(BASERUBY)
	@for %I in (ruby.exe) do @echo BASERUBY = %~s$$PATH:I>> $(MAKEFILE)
	@echo !if "$$(BASERUBY)" == "">> $(MAKEFILE)
	@echo BASERUBY = echo executable host ruby is required.  use --with-baseruby option.^& exit 1 >> $(MAKEFILE)
	@echo !endif>> $(MAKEFILE)
!endif

-system-vars-: -osname- -runtime-

-system-vars32-: -osname32- -runtime-

-system-vars64-: -osname64- -runtime-

-osname32-: nul
	@echo TARGET_OS = mswin32>>$(MAKEFILE)

-osname64-: nul
	@echo TARGET_OS = mswin64>>$(MAKEFILE)

-osname-: nul
	@echo !ifndef TARGET_OS>>$(MAKEFILE)
	@($(CC) -c <<conftest.c > nul && (echo TARGET_OS = mswin32) || (echo TARGET_OS = mswin64)) >>$(MAKEFILE)
#ifdef _WIN64
#error
#endif
<<
	@echo !endif>>$(MAKEFILE)
	@$(WIN32DIR:/=\)\rm.bat conftest.*

-runtime-: nul
	@$(CC) -MD <<conftest.c user32.lib -link > nul
#include <stdio.h>
int main(void) {FILE *volatile f = stdin; return 0;}
<<
	@$(WIN32DIR:/=\)\rtname conftest.exe >>$(MAKEFILE)
	@$(WIN32DIR:/=\)\rm.bat conftest.*

-version-: nul
	@$(APPEND)
	@$(CPP) -I$(srcdir) -I$(srcdir)/include <<"Creating $(MAKEFILE)" | findstr "=" >>$(MAKEFILE)
#define RUBY_REVISION 0
#include "version.h"
MAJOR = RUBY_API_VERSION_MAJOR
MINOR = RUBY_API_VERSION_MINOR
TEENY = RUBY_API_VERSION_TEENY
MSC_VER = _MSC_VER
<<

-program-name-:
	@type << >>$(MAKEFILE)
!ifdef PROGRAM_PREFIX
PROGRAM_PREFIX = $(PROGRAM_PREFIX)
!endif
!ifdef PROGRAM_SUFFIX
PROGRAM_SUFFIX = $(PROGRAM_SUFFIX)
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
!if "$(PROCESSOR_ARCHITECTURE)" == "AMD64"
$(ARCH) = x64
!elseif "$(PROCESSOR_ARCHITECTURE)" == "IA64"
$(ARCH) = ia64
!elseif defined(PROCESSOR_ARCHITEW6432)
$(BANG)if "$$(TARGET_OS)" == "mswin64"
!if "$(PROCESSOR_ARCHITECTURE)" == "IA64"
$(ARCH) = ia64
!else
$(ARCH) = x64
!endif
$(BANG)else
$(ARCH) = $(PROCESSOR_ARCHITECTURE)
$(BANG)endif
!else
$(ARCH) = $(PROCESSOR_ARCHITECTURE)
!endif
!endif
!if defined($(CPU))
$(CPU) = $(PROCESSOR_LEVEL)
!endif

<<
!endif

-alpha-: nul
	@echo $(ARCH) = alpha>>$(MAKEFILE)
-x64-: nul
	@echo $(ARCH) = x64>>$(MAKEFILE)
-ia64-: nul
	@echo $(ARCH) = ia64>>$(MAKEFILE)
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

-epilogue-: -encs-

-encs-: nul
	@$(MAKE) -l -f $(srcdir)/win32/enc-setup.mak srcdir="$(srcdir)" MAKEFILE=$(MAKEFILE)

-epilogue-: nul
!if exist(confargs.c)
	@$(APPEND)
	@$(CPP) confargs.c 2>&1 | findstr "! =" >> $(MAKEFILE)
	@del confargs.c
!endif
	@type << >>$(MAKEFILE)

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
	@echo "type `nmake' to make ruby."
