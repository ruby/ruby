# -*- makefile -*-

!IF "$(WIN32DIR)" == "win32"
srcdir = .
!ELSEIF "$(WIN32DIR)" == "$(WIN32DIR:/win32=)/win32"
srcdir = $(WIN32DIR:/win32=)
!ELSE
srcdir = $(WIN32DIR)/..
!ENDIF
OS = mswin32

all: config.h config.status
all: ext
all: Makefile
all:; @echo type `nmake' to make ruby for mswin32.

Makefile:
	@echo ### makefile for ruby $(OS) ###> $@
	@echo srcdir = $(srcdir:\=/)>> $@
	@echo RUBY_INSTALL_NAME = ruby>> $@
	@echo RUBY_SO_NAME = $(OS)-$$(RUBY_INSTALL_NAME)16>> $@
	@echo !INCLUDE $$(srcdir)/win32/Makefile.sub>> $@

config.h config.status: $(srcdir)/win32/$$@.in
	@copy $(srcdir:/=\)\win32\$@.in $@ > nul

ext:;	@if not exist $@\* mkdir $@
