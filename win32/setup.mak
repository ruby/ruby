# -*- makefile -*-

!IF "$(WIN32DIR)" == "win32"
srcdir = .
!ELSEIF "$(WIN32DIR)" == "$(WIN32DIR:/win32=)/win32"
srcdir = $(WIN32DIR:/win32=)
!ELSE
srcdir = $(WIN32DIR)/..
!ENDIF
OS = mswin32

all: ext
all: Makefile
all:; @echo type `nmake' to make ruby for mswin32.

Makefile:
	@echo ### makefile for ruby $(OS) ###> $@
	@echo srcdir = $(srcdir:\=/)>> $@
	@echo RUBY_INSTALL_NAME = ruby>> $@
	@echo RUBY_SO_NAME = $(OS)-$$(RUBY_INSTALL_NAME)17>> $@
	@echo prefix = /usr>> $@
	@echo CFLAGS = -nologo -MD -DNT=1 $$(DEBUGFLAGS) $$(OPTFLAGS) $$(PROCESSOR_FLAG)>> $@
	@echo CPPFLAGS = -I. -I$$(srcdir) -I$$(srcdir)/missing -DLIBRUBY_SO=\"$$(LIBRUBY_SO)\">> $@
	@echo LDFLAGS = $$(CFLAGS) -Fm>> $@
	@echo XLDFLAGS = >> $@
	@echo RFLAGS = -r>> $@
	@echo EXTLIBS =>> $@
	@echo !INCLUDE $$(srcdir)/win32/Makefile.sub>> $@

ext:;	@if not exist $@\* mkdir $@
