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
OS = mswin32
RT = msvcrt
INCLUDE = !include
APPEND = echo>>$(MAKEFILE)
!ifdef MAKEFILE
MAKE = $(MAKE) -f $(MAKEFILE)
!else
MAKEFILE = Makefile
!endif
ARCH = PROCESSOR_ARCHITECTURE
CPU = PROCESSOR_LEVEL

all: -prologue- -generic- -epilogue-
i386-$(OS): -prologue- -i386- -epilogue-
i486-$(OS): -prologue- -i486- -epilogue-
i586-$(OS): -prologue- -i586- -epilogue-
i686-$(OS): -prologue- -i686- -epilogue-
alpha-$(OS): -prologue- -alpha- -epilogue-

-prologue-: nul
	@type << > $(MAKEFILE)
### Makefile for ruby $(OS) ###
srcdir = $(srcdir:\=/)
<<
	@cl -nologo -EP -I$(srcdir) -DRUBY_EXTERN="//" <<"Creating $(MAKEFILE)" >> $(MAKEFILE)
#include "version.h"
MAJOR = RUBY_VERSION_MAJOR
MINOR = RUBY_VERSION_MINOR
TEENY = RUBY_VERSION_TEENY
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
	@type << >>$(MAKEFILE)
# OS = $(OS)
# RT = $(RT)
# RUBY_INSTALL_NAME = ruby
# RUBY_SO_NAME = $$(RT)-$$(RUBY_INSTALL_NAME)$$(MAJOR)$$(MINOR)
# prefix = /usr
# CFLAGS = -nologo -MD $$(DEBUGFLAGS) $$(OPTFLAGS) $$(PROCESSOR_FLAG)
# CPPFLAGS = -I. -I$$(srcdir) -I$$(srcdir)/missing -DLIBRUBY_SO=\"$$(LIBRUBY_SO)\"
# STACK = 0x2000000
# LDFLAGS = $$(CFLAGS) -Fm
# XLDFLAGS = 
# RFLAGS = -r
# EXTLIBS =

$(INCLUDE) $$(srcdir)/win32/Makefile.sub
<<
	@if exist config.h del config.h
	@if exist config.status del config.status
	@echo type `$(MAKE)' to make ruby for $(OS).
