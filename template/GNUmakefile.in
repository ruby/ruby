override MFLAGS := $(filter-out -j%,$(MFLAGS))
override MAKEFLAGS := $(filter-out -j%,$(MAKEFLAGS))
include Makefile
-include uncommon.mk
include $(srcdir)/defs/gmake.mk

GNUmakefile: $(srcdir)/template/GNUmakefile.in
