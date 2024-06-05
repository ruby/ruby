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
!if defined(RJIT_SUPPORT)
RJIT_SUPPORT = $(RJIT_SUPPORT)
!endif
!if defined(XINCFLAGS)
CPPFLAGS = $(XINCFLAGS)
!endif
!if defined(XLDFLAGS)
XLDFLAGS = $(XLDFLAGS)
!endif

# TOOLS
<<
!if defined(BASERUBY)
	$(BASERUBY:/=\) "$(srcdir)/tool/missing-baseruby.bat"
	@echo BASERUBY = $(BASERUBY:/=\)>> $(MAKEFILE)
!endif
!if "$(RUBY_DEVEL)" == "yes"
	RUBY_DEVEL = yes
!endif
!if "$(GIT)" != ""
	@echo GIT = $(GIT)>> $(MAKEFILE)
!endif
!if "$(HAVE_GIT)" != ""
	@echo HAVE_GIT = $(HAVE_GIT)>> $(MAKEFILE)
!endif

!if "$(WITH_GMP)" != "no"
	@($(CC) $(XINCFLAGS) <<conftest.c -link $(XLDFLAGS) gmp.lib > nul && (echo USE_GMP = yes) || (echo USE_GMP = no)) >>$(MAKEFILE)
#include <gmp.h>
mpz_t x;
int main(void) {mpz_init(x); return 0;}
<<
	@$(WIN32DIR:/=\)\rm.bat conftest.*
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

-headers-: vs2022-fp-bug

# Check the bug reported at:
# https://developercommunity.visualstudio.com/t/With-__assume-isnan-after-isinf/1515649
# https://developercommunity.visualstudio.com/t/Prev-Issue---with-__assume-isnan-/1597317
vs2022-fp-bug:
	@echo checking for $(@:-= )
	@echo <<$@.c > NUL
/* compile with -O2 */
#include <math.h>
#include <float.h>
#include <stdio.h>

#define value_finite(d) 'f'
#define value_infinity() 'i'
#define value_nan() 'n'

#ifdef NO_ASSUME
# define ASSUME_TRUE() (void)0
#else
# define ASSUME_TRUE() __assume(1)
#endif

static int
check_value(double value)
{
    if (isinf(value)) {
        return value_infinity();
    }
    else if (isnan(value)) {
        return value_nan();
    }

    ASSUME_TRUE();
    return value_finite(value);
}

int
main(void)
{
    int c = check_value(nan(""));
    printf("NaN=>%c\n", c);
    return c != value_nan();
}
<<
	@( \
	  $(CC) -O2 $@.c && .\$@ || \
	  set bug=%ERRORLEVEL% \
	  echo This compiler has an optimization bug \
	) & $(WIN32DIR:/=\)\rm.bat $@.* & exit /b %bug%

-version-: nul verconf.mk

verconf.mk: nul
	@findstr /R /C:"^#define RUBY_ABI_VERSION " $(srcdir:/=\)\include\ruby\internal\abi.h > $(@)
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
#include "$(@F)"
echo ABI_VERSION = RUBY_ABI_VERSION
#endif
set /a MSC_VER = _MSC_VER
#if _MSC_VER >= 1920
set /a MSC_VER_LOWER = MSC_VER/20*20+0
set /a MSC_VER_UPPER = MSC_VER/20*20+19
#elif _MSC_VER >= 1900
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
	@type << >>$(MAKEFILE)

$(BANG)include $$(srcdir)/win32/Makefile.sub
<<
	@$(COMSPEC) /C $(srcdir:/=\)\win32\rm.bat config.h config.status
	@echo "type `nmake' to make ruby."
