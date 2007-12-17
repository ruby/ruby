!include $(srcdir)/enc/Makefile.in

all:
	@echo BUILTIN_ENCOBJS = $(BUILTIN_ENCS:.c=.obj) >> $(MAKEFILE)
