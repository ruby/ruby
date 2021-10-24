gnumake = yes

ifeq ($(filter Makefile,$(MAKEFILE_LIST)),)
include Makefile

GNUmakefile: $(srcdir)/template/GNUmakefile.in
endif

override silence := $(if $(findstring s,$(firstword $(MFLAGS))),yes,no)

ifeq ($(HAVE_BASERUBY),yes)
override REVISION_FORCE := PHONY
endif

include $(srcdir)/defs/universal.mk
-include uncommon.mk
include $(srcdir)/defs/gmake.mk

GNUmakefile: $(srcdir)/template/GNUmakefile.in
