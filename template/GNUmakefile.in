include Makefile

ifeq ($(HAVE_BASERUBY),yes)
override REVISION_FORCE := PHONY
endif

include $(srcdir)/defs/universal.mk
-include uncommon.mk
include $(srcdir)/defs/gmake.mk

GNUmakefile: $(srcdir)/template/GNUmakefile.in
