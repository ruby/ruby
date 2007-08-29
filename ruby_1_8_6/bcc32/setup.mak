# -*- makefile -*-

!if "$(srcdir)" != ""
bcc32dir = $(srcdir)/bcc32
!elseif "$(bcc32dir)" == "bcc32/"
srcdir = .
!elseif "$(bcc32dir:/bcc32/=)/bcc32/" == "$(bcc32dir)"
srcdir = $(bcc32dir:/bcc32/=)
!else
srcdir = $(bcc32dir)/..
!endif
!ifndef prefix
prefix = /usr
!endif
OS = bccwin32
RT = $(OS)
BANG = !
APPEND = echo>>$(MAKEFILE)
!ifdef MAKEFILE
MAKE = $(MAKE) -f $(MAKEFILE)
!else
MAKEFILE = Makefile
!endif

all: Makefile
Makefile: -prologue- -generic- -epilogue-
i386-$(OS): -prologue- -i386- -epilogue-
i486-$(OS): -prologue- -i486- -epilogue-
i586-$(OS): -prologue- -i586- -epilogue-
i686-$(OS): -prologue- -i686- -epilogue-
alpha-$(OS): -prologue- -alpha- -epilogue-

-prologue-: nul
	@echo Creating $(MAKEFILE)
	@type > $(MAKEFILE) &&|
\#\#\# Makefile for ruby $(OS) \#\#\#
$(BANG)ifndef srcdir
srcdir = $(srcdir:\=/)
$(BANG)endif
$(BANG)ifndef prefix
prefix = $(prefix:\=/)
$(BANG)endif
$(BANG)ifndef EXTSTATIC
EXTSTATIC = $(EXTSTATIC)
$(BANG)endif
!if defined(RDOCTARGET)
$(BANG)ifndef RDOCTARGET
RDOCTARGET = $(RDOCTARGET)
$(BANG)endif
!endif
!if defined(EXTOUT)
$(BANG)ifndef EXTOUT
EXTOUT = $(EXTOUT)
$(BANG)endif
!endif
|
	@type > usebormm.bat &&|
@echo off
ilink32 -Gn -x usebormm.lib > nul
if exist usebormm.tds echo MEMLIB = usebormm.lib
|
	@usebormm.bat >> $(MAKEFILE)
	@del usebormm.*

	@cpp32 -I$(srcdir) -P- -o$(MAKEFILE) > nul &&|
\#include "version.h"
MAJOR = RUBY_VERSION_MAJOR
MINOR = RUBY_VERSION_MINOR
TEENY = RUBY_VERSION_TEENY
|
	@type $(MAKEFILE).i >> $(MAKEFILE)
	@del $(MAKEFILE).i

-generic-: nul
!if defined(PROCESSOR_ARCHITECTURE) ||  defined(PROCESSOR_LEVEL)
	@type >> $(MAKEFILE) &&|
!if defined(PROCESSOR_ARCHITECTURE)
$(BANG)ifndef PROCESSOR_ARCHITECTURE
PROCESSOR_ARCHITECTURE = $(PROCESSOR_ARCHITECTURE)
$(BANG)endif
!endif
!if defined(PROCESSOR_LEVEL)
$(BANG)ifndef PROCESSOR_LEVEL
PROCESSOR_LEVEL = $(PROCESSOR_LEVEL)
$(BANG)endif
!endif

|
!endif

-alpha-: nul
	@$(APPEND) !ifndef PROCESSOR_ARCHITECTURE
	@$(APPEND) PROCESSOR_ARCHITECTURE = alpha
	@$(APPEND) !endif
-ix86-: nul
	@$(APPEND) !ifndef PROCESSOR_ARCHITECTURE
	@$(APPEND) PROCESSOR_ARCHITECTURE = x86
	@$(APPEND) !endif

-i386-: -ix86-
	@$(APPEND) !ifndef PROCESSOR_LEVEL
	@$(APPEND) PROCESSOR_LEVEL = 3
	@$(APPEND) !endif
-i486-: -ix86-
	@$(APPEND) !ifndef PROCESSOR_LEVEL
	@$(APPEND) PROCESSOR_LEVEL = 4
	@$(APPEND) !endif
-i586-: -ix86-
	@$(APPEND) !ifndef PROCESSOR_LEVEL
	@$(APPEND) PROCESSOR_LEVEL = 5
	@$(APPEND) !endif
-i686-: -ix86-
	@$(APPEND) !ifndef PROCESSOR_LEVEL
	@$(APPEND) PROCESSOR_LEVEL = 6
	@$(APPEND) !endif

-epilogue-: nul
	@type >> $(MAKEFILE) &&|

\# OS = $(OS)
\# RT = $(RT)
\# RUBY_INSTALL_NAME = ruby
\# RUBY_SO_NAME = $$(RT)-$$(RUBY_INSTALL_NAME)$$(MAJOR)$$(MINOR)
\# CFLAGS = -q $$(DEBUGFLAGS) $$(OPTFLAGS) $$(PROCESSOR_FLAG) -w- -wsus -wcpt -wdup -wext -wrng -wrpt -wzdi
\# CPPFLAGS = -I. -I$$(srcdir) -I$$(srcdir)/missing -DLIBRUBY_SO=\"$$(LIBRUBY_SO)\"
\# STACK = 0x2000000
\# LDFLAGS = -S:$$(STACK)
\# RFLAGS = $$(iconinc)
\# EXTLIBS = cw32.lib import32.lib user32.lib kernel32.lib
$(BANG)include $$(srcdir)/bcc32/Makefile.sub
|
	@$(srcdir:/=\)\win32\rm.bat config.h config.status
	@echo type "`$(MAKE)'" to make ruby for $(OS).
