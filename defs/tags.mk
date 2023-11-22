# -*- mode: makefile-gmake; indent-tabs-mode: t -*-

SRCS := $(shell $(GIT) ls-files \
	*.[chy] *.def *.inc *.rb \
	ccan/ coroutine/ include/ internal/ missing/ \
	'enc/**/*.[ch]' 'win32/**/*.[ch]' \
	)

TAGS: $(SRCS)
	@echo updating $@
	@tmp=$$(mktemp); \
	trap 'rm -f "$$tmp"' 0; \
	{ \
	  $(GIT) grep -h --no-line-number -o '^ *# *define  *RBIMPL_ATTR_[A-Z_]*(*' -- include | \
	    sed 's/^ *# *define *//;/_H$$/d;y/(/+/' | sort -u && \
	  echo 'NORETURN+'; \
	} > "$$tmp" && \
	ctags -e -I@"$$tmp" -h .def.inc --langmap=c:+.y.def.inc $(^)
