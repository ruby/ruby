override MFLAGS := $(filter-out -j%,$(MFLAGS))
include Makefile
-include uncommon.mk
include $(srcdir)/defs/gmake.mk

GNUmakefile: $(srcdir)/template/GNUmakefile.in
