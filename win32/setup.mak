# -*- makefile -*-

!IF "$(WIN32DIR)" == "win32"
srcdir = .
!ELSEIF "$(WIN32DIR)" == "$(WIN32DIR:/win32=)/win32"
srcdir = $(WIN32DIR:/win32=)
!ELSE
srcdir = $(WIN32DIR)/..
!ENDIF
OS = mswin32
RT = msvcrt
INCLUDE = !include
MAKEFILE = $(WIN32DIR)/setup.mak

!if "$(target)" == ""
all: Makefile
	@echo type `$(MAKE)' to make ruby for $(OS).
!else
all: $(target)
!endif

i386-$(OS):
	@$(MAKE) -$(MAKEFLAGS) -f $(MAKEFILE) target= \
		PROCESSOR_ARCHITECTURE=x86 PROCESSOR_LEVEL=3
i486-$(OS):
	@$(MAKE) -$(MAKEFLAGS) -f $(MAKEFILE) target= \
		PROCESSOR_ARCHITECTURE=x86 PROCESSOR_LEVEL=4
i586-$(OS):
	@$(MAKE) -$(MAKEFLAGS) -f $(MAKEFILE) target= \
		PROCESSOR_ARCHITECTURE=x86 PROCESSOR_LEVEL=5
i686-$(OS):
	@$(MAKE) -$(MAKEFLAGS) -f $(MAKEFILE) target= \
		PROCESSOR_ARCHITECTURE=x86 PROCESSOR_LEVEL=6
alpha-$(OS):
	@$(MAKE) -$(MAKEFLAGS) -f $(MAKEFILE) target= \
		PROCESSOR_ARCHITECTURE=alpha PROCESSOR_LEVEL=

Makefile:
	@echo Creating <<$@
### Makefile for ruby $(OS) ###
srcdir = $(srcdir:\=/)
!if defined(PROCESSOR_ARCHITECTURE)
PROCESSOR_ARCHITECTURE = $(PROCESSOR_ARCHITECTURE)
!endif
!if defined(PROCESSOR_LEVEL)
PROCESSOR_LEVEL = $(PROCESSOR_LEVEL)
!endif
RUBY_INSTALL_NAME = ruby
RUBY_SO_NAME = $(RT)-$$(RUBY_INSTALL_NAME)17
prefix = /usr
CFLAGS = -nologo -MD -DNT=1 $$(DEBUGFLAGS) $$(OPTFLAGS) $$(PROCESSOR_FLAG)
CPPFLAGS = -I. -I$$(srcdir) -I$$(srcdir)/missing -DLIBRUBY_SO=\"$$(LIBRUBY_SO)\"
LDFLAGS = $$(CFLAGS) -Fm
XLDFLAGS = 
RFLAGS = -r
EXTLIBS =
$(INCLUDE) $$(srcdir)/win32/Makefile.sub
<<KEEP
