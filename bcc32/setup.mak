# -*- makefile -*-

!if "$(bcc32dir)" == "bcc32/"
srcdir = ./
!elseif "$(bcc32dir)" == "../bcc32/"
srcdir = ../
!else
srcdir = $(bcc32dir)../
!endif

OS = bccwin32

all: ext makefile
	@echo type `make' to make ruby for bccwin32.

makefile: make_s make_e

make_s:
	@if exist makefile @del makefile
	@echo ### makefile for ruby $(OS) ###> makefile
	@echo srcdir = $(srcdir:\=/)>> makefile
	@echo RUBY_INSTALL_NAME = ruby>> makefile
	@echo RUBY_SO_NAME = $(OS)_$$(RUBY_INSTALL_NAME)17>> makefile

make_e:
	@echo !INCLUDE $$(srcdir)bcc32/makefile.sub>> makefile

ext:
	@if not exist $@\* mkdir $@

pl3:
	@echo PROCESSOR_LEVEL = 3 >> makefile

pl4:
	@echo PROCESSOR_LEVEL = 4 >> makefile

pl5:
	@echo PROCESSOR_LEVEL = 5 >> makefile

pl6:
	@echo PROCESSOR_LEVEL = 6 >> makefile

3: ext make_s pl3 make_e

4: ext make_s pl4 make_e

5: ext make_s pl5 make_e

6: ext make_s pl6 make_e

