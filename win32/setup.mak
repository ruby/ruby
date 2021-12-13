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
CC = $(CC) -nologo
CPP = $(CC) -EP

all: -prologue- -generic- -epilogue-
i386-mswin32: -prologue- -i386- -epilogue-
i486-mswin32: -prologue- -i486- -epilogue-
i586-mswin32: -prologue- -i586- -epilogue-
i686-mswin32: -prologue- -i686- -epilogue-
alpha-mswin32: -prologue- -alpha- -epilogue-
x64-mswin64: -prologue- -x64- -epilogue-

-prologue-: -basic-vars-
-generic-: -osname-

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
!if defined(EXTOUT) && "$(EXTOUT)" != ".ext"
EXTOUT = $(EXTOUT)
!endif
!if defined(NTVER)
NTVER = $(NTVER)
!endif
!if defined(USE_RUBYGEMS)
USE_RUBYGEMS = $(USE_RUBYGEMS)
!endif
!if defined(ENABLE_DEBUG_ENV)
ENABLE_DEBUG_ENV = $(ENABLE_DEBUG_ENV)
!endif
!if defined(MJIT_SUPPORT)
MJIT_SUPPORT = $(MJIT_SUPPORT)
!endif

# TOOLS
<<
!if defined(BASERUBY)
	@echo BASERUBY = $(BASERUBY:/=\)>> $(MAKEFILE)
!else
	@for %I in (ruby.exe) do @echo BASERUBY = %~s$$PATH:I>> $(MAKEFILE)
!endif
	@type << >> $(MAKEFILE)
$(BANG)if "$$(BASERUBY)" == ""
BASERUBY = echo executable host ruby is required.  use --with-baseruby option.^& exit 1
HAVE_BASERUBY = no
$(BANG)elseif [($$(BASERUBY) -eexit) > nul 2> nul] == 0
HAVE_BASERUBY = yes
$(BANG)else
HAVE_BASERUBY = no
$(BANG)endif
<<
!if "$(GIT)" != ""
	@echo GIT = $(GIT)>> $(MAKEFILE)
!endif
!if "$(HAVE_GIT)" != ""
	@echo HAVE_GIT = $(HAVE_GIT)>> $(MAKEFILE)
!endif

-osname-section-:
	@$(APPEND)
	@echo # TARGET>>$(MAKEFILE)

-osname32-: -osname-section-
	@echo TARGET_OS = mswin32>>$(MAKEFILE)

-osname64-: -osname-section-
	@echo TARGET_OS = mswin64>>$(MAKEFILE)

-osname-: -osname-section-
	@echo !ifndef TARGET_OS>>$(MAKEFILE)
	@($(CC) -c <<conftest.c > nul && (echo TARGET_OS = mswin32) || (echo TARGET_OS = mswin64)) >>$(MAKEFILE)
#ifdef _WIN64
#error
#endif
<<
	@echo !endif>>$(MAKEFILE)
	@$(WIN32DIR:/=\)\rm.bat conftest.*

-compiler-: -compiler-section- -version- -runtime- -headers-

-compiler-section-:
	@$(APPEND)
	@echo # COMPILER>>$(MAKEFILE)

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

verconf.mk: nul
	@$(CPP) -I$(srcdir) -I$(srcdir)/include <<"Creating $(@)" > $(*F).bat && cmd /c $(*F).bat > $(@)
@echo off
#define RUBY_REVISION 0
#define STRINGIZE0(expr) #expr
#define STRINGIZE(x) STRINGIZE0(x)
#include "version.h"
set ruby_release_year=RUBY_RELEASE_YEAR
set ruby_release_month=RUBY_RELEASE_MONTH
set ruby_release_day=RUBY_RELEASE_DAY
set ruby_release_month=0%ruby_release_month%
set ruby_release_day=0%ruby_release_day%
#undef RUBY_RELEASE_YEAR
#undef RUBY_RELEASE_MONTH
#undef RUBY_RELEASE_DAY
echo RUBY_RELEASE_YEAR = %ruby_release_year%
echo RUBY_RELEASE_MONTH = %ruby_release_month:~-2%
echo RUBY_RELEASE_DAY = %ruby_release_day:~-2%
echo MAJOR = RUBY_VERSION_MAJOR
echo MINOR = RUBY_VERSION_MINOR
echo TEENY = RUBY_VERSION_TEENY
#if defined RUBY_PATCHLEVEL && RUBY_PATCHLEVEL < 0
echo RUBY_DEVEL = yes
#endif
set /a MSC_VER = _MSC_VER
#if _MSC_VER > 1900
set /a MSC_VER_LOWER = MSC_VER/10*10+0
set /a MSC_VER_UPPER = MSC_VER/10*10+9
#endif
set MSC_VER
del %0 & exit
<<

-program-name-:
	@type << >>$(MAKEFILE)

# PROGRAM-NAME
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
#else
MACHINE = x86
#endif
<<
!if defined($(CPU))
	@echo>>$(MAKEFILE) $(CPU) = $(PROCESSOR_LEVEL)
!endif

-alpha-: -osname32-
	@echo MACHINE = alpha>>$(MAKEFILE)
-x64-: -osname64-
	@echo MACHINE = x64>>$(MAKEFILE)
-ix86-: -osname32-
	@echo MACHINE = x86>>$(MAKEFILE)

-i386-: -ix86-
	@echo $(CPU) = 3>>$(MAKEFILE)
-i486-: -ix86-
	@echo $(CPU) = 4>>$(MAKEFILE)
-i586-: -ix86-
	@echo $(CPU) = 5>>$(MAKEFILE)
-i686-: -ix86-
	@echo $(CPU) = 6>>$(MAKEFILE)

-epilogue-: -compiler- -program-name- -encs-

-encs-: nul
	@$(APPEND)
	@echo # ENCODING>>$(MAKEFILE)
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
CC = $(CC)
!if "$(AS)" != "ml64"
AS = $(AS) -nologo
!endif
<<
!if "$(AS)" == "ml64"
	@(findstr -r -c:"^MACHINE *= *x86" $(MAKEFILE) > nul && \
	(echo AS = $(AS:64=) -nologo) || \
	(echo AS = $(AS) -nologo) ) >>$(MAKEFILE)
!endif
	@(for %I in (cl.exe) do @set MJIT_CC=%~$$PATH:I) && (call echo MJIT_CC = "%MJIT_CC:\=/%" -nologo>>$(MAKEFILE))
	@type << >>$(MAKEFILE)

$(BANG)include $$(srcdir)/win32/Makefile.sub
<<
	@$(COMSPEC) /C $(srcdir:/=\)\win32\rm.bat config.h config.status
	@echo "type `nmake' to make ruby."
