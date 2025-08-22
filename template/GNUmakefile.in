gnumake = yes

ifneq ($(filter notintermediate,$(.FEATURES)),)
DOT_WAIT = .WAIT
endif

ifeq ($(filter Makefile,$(MAKEFILE_LIST)),)
include Makefile
endif

GNUmakefile: $(srcdir)/template/GNUmakefile.in

override silence := $(if $(findstring s,$(firstword $(MFLAGS))),yes,no)

ifeq ($(HAVE_BASERUBY),yes)
override REVISION_FORCE := PHONY
endif

override order_only := |

# Needs the dependency when any Unicode tables data files exist.
override UNICODE_TABLES_DEPENDENTS = \
	$(if $(or \
	    $(filter yes,$(ALWAYS_UPDATE_UNICODE)), \
	    $(wildcard \
		$(if $(filter .,$(UNICODE_FILES) $(UNICODE_PROPERTY_FILES)),,\
		    $(UNICODE_TABLES_DATA_FILES)))),\
	    force,none)

-include uncommon.mk
include $(srcdir)/defs/gmake.mk
