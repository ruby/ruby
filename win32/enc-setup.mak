BUILTIN_ENCOBJS:

!include $(srcdir)/enc/Makefile.in

BUILTIN_ENCOBJS: $(srcdir)/enc/Makefile.in
	@echo BUILTIN_ENCOBJS = $(BUILTIN_ENCS:.c=.obj) >> $(MAKEFILE)
