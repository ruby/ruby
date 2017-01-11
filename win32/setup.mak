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
!if defined(libdir_basename)
libdir_basename = $(libdir_basename)
!endif
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
	@echo HAVE_BASERUBY = no>> $(MAKEFILE)
	@echo !else>> $(MAKEFILE)
	@echo HAVE_BASERUBY = yes>> $(MAKEFILE)
	@echo !endif>> $(MAKEFILE)
!elseif [$(BASERUBY) -eexit 2> nul] == 0
	@echo HAVE_BASERUBY = yes>> $(MAKEFILE)
!else
	@echo HAVE_BASERUBY = no>> $(MAKEFILE)
!endif

-system-vars-: -osname- -runtime- -headers-

-system-vars32-: -osname32- -runtime- -headers-

-system-vars64-: -osname64- -runtime- -headers-

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

-headers-: nul

check-psapi.h: nul
	($(CC) -MD <<conftest.c psapi.lib -link && echo>>$(MAKEFILE) HAVE_PSAPI_H=1) & $(WIN32DIR:/=\)\rm.bat conftest.*
#include <windows.h>
#include <psapi.h>
int main(void) {return (EnumProcesses(NULL,0,NULL) ? 0 : 1);}
<<

-version-: nul verconf.mk
	@$(APPEND)
	@$(CPP) -I$(srcdir) -I$(srcdir)/include <<"Creating $(MAKEFILE)" | findstr "=" >>$(MAKEFILE)
MSC_VER = _MSC_VER
<<

verconf.mk: nul
	@$(CPP) -I$(srcdir) -I$(srcdir)/include <<"Creating $(@)" > $(*F).bat && cmd /c $(*F).bat > $(@)
@echo off
#define RUBY_REVISION 0
#define STRINGIZE0(expr) #expr
#define STRINGIZE(x) STRINGIZE0(x)
#include "version.h"
for %%I in (RUBY_RELEASE_DATE) do set ruby_release_date=%%~I
for %%I in (RUBY_VERSION) do set ruby_version=%%~I
for /f "delims=. tokens=1-3" %%I in (RUBY_VERSION) do (
    set major=%%I
    set minor=%%J
    set teeny=%%K
)
#undef RUBY_RELEASE_DATE
#undef RUBY_PROGRAM_VERSION
echo RUBY_RELEASE_DATE = %ruby_release_date:""=%
echo RUBY_PROGRAM_VERSION = %ruby_version:""=%
echo MAJOR = %major%
echo MINOR = %minor%
echo TEENY = %teeny%
del %0 & exit
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
	@$(CPP) <<conftest.c 2>nul | findstr = >>$(MAKEFILE)
#if defined _M_X64
MACHINE = x64
#elif defined _M_IA64
MACHINE = ia64
#else
MACHINE = x86
#endif
<<
!if defined($(CPU))
	@echo>>$(MAKEFILE) $(CPU) = $(PROCESSOR_LEVEL)
!endif
	@$(APPEND)

-alpha-: nul
	@echo MACHINE = alpha>>$(MAKEFILE)
-x64-: nul
	@echo MACHINE = x64>>$(MAKEFILE)
-ia64-: nul
	@echo MACHINE = ia64>>$(MAKEFILE)
-ix86-: nul
	@echo MACHINE = x86>>$(MAKEFILE)

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
# CFLAGS = $$(RUNTIMEFLAG) $$(DEBUGFLAGS) $$(WARNFLAGS) $$(OPTFLAGS) $$(PROCESSOR_FLAG) $$(COMPILERFLAG)
# CPPFLAGS =
# STACK = 0x2000000
# LDFLAGS = $$(CFLAGS) -Fm
# XLDFLAGS =
# RFLAGS = -r
# EXTLIBS =
CC = cl -nologo

$(BANG)include $$(srcdir)/win32/Makefile.sub
<<
	@$(COMSPEC) /C $(srcdir:/=\)\win32\rm.bat config.h config.status
	@echo "type `nmake' to make ruby."
