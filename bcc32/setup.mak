# -*- makefile -*-

!if "$(srcdir)" != ""
bcc32dir = $(srcdir)bcc32/
!elseif "$(bcc32dir)" == "bcc32/"
srcdir = ./
!elseif "$(bcc32dir:/bcc32/=)/bcc32/" == "$(bcc32dir)"
srcdir = $(bcc32dir:/bcc32/=/)
!else
srcdir = $(bcc32dir)../
!endif

OS = bccwin32
RT = $(OS)
INCLUDE = !include
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
srcdir = $(srcdir:\=/)
|
	@cpp32 -I$(srcdir) -DRUBY_EXTERN="//" -P- -o$(MAKEFILE) > nul &&|
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
PROCESSOR_ARCHITECTURE = $(PROCESSOR_ARCHITECTURE)
!endif
!if defined(PROCESSOR_LEVEL)
PROCESSOR_LEVEL = $(PROCESSOR_LEVEL)
!endif

|
!endif

-alpha-: nul
	@$(APPEND) PROCESSOR_ARCHITECTURE = alpha
-ix86-: nul
	@$(APPEND) PROCESSOR_ARCHITECTURE = x86

-i386-: -ix86-
	@$(APPEND) PROCESSOR_LEVEL = 3
-i486-: -ix86-
	@$(APPEND) PROCESSOR_LEVEL = 4
-i586-: -ix86-
	@$(APPEND) PROCESSOR_LEVEL = 5
-i686-: -ix86-
	@$(APPEND) PROCESSOR_LEVEL = 6

-epilogue-: nul
	@type >> $(MAKEFILE) &&|

\# OS = $(OS)
\# RT = $(RT)
\# RUBY_INSTALL_NAME = ruby
\# RUBY_SO_NAME = $$(RT)-$$(RUBY_INSTALL_NAME)$$(MAJOR)$$(MINOR)
\# prefix = /usr
\# CFLAGS = -q $$(DEBUGFLAGS) $$(OPTFLAGS) $$(PROCESSOR_FLAG) -w- -wsus -wcpt -wdup -wext -wrng -wrpt -wzdi
\# CPPFLAGS = -I. -I$$(srcdir) -I$$(srcdir)missing -DLIBRUBY_SO=\"$$(LIBRUBY_SO)\"
\# STACK = 0x2000000
\# LDFLAGS = -S:$$(STACK)
\# RFLAGS = $$(iconinc)
\# EXTLIBS = cw32.lib import32.lib user32.lib kernel32.lib
$(INCLUDE) $$(srcdir)bcc32/Makefile.sub
|
	@if exist config.h del config.h
	@if exist config.status del config.status
	@echo type "`$(MAKE)'" to make ruby for $(OS).
