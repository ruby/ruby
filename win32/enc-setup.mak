BUILTIN_ENCOBJS:

!include $(srcdir)/enc/Makefile.in

BUILTIN_ENCOBJS:
	@echo BUILTIN_ENCOBJS = $(BUILTIN_ENCS:.c=.obj) >> $(MAKEFILE)
