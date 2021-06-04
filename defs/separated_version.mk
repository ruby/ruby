# ******** FOR DEVELEPERS ONLY ********
# Separate version.o into a shared library which varies every
# revisions, in order to make the rest shareable.

include $(firstword $(wildcard GNUmakefile Makefile))

ifneq ($(filter @executable_path/%,$(DLDFLAGS)),)
RUBY_VERSION_SO = $(subst ruby,ruby_version,$(LIBRUBY_SO))
RUBY_VERSION_DLDFLAGS := $(patsubst @executable_path/%/$(LIBRUBY_SO),@loader_path/$(RUBY_VERSION_SO),$(DLDFLAGS)) -exported_symbol=Init_version
else ifneq ($(findstring -soname,$(DLDFLAGS)),)
RUBY_VERSION_SO = $(subst ruby,ruby_version,$(LIBRUBY_SO))
RUBY_VERSION_DLDFLAGS := $(subst ruby,ruby_version,$(DLDFLAGS)) -Wl,-rpath-link,'$${ORIGIN}'
else
ERROR
endif

ifneq ($(RUBY_VERSION_SO),)

version.$(OBJEXT): XCFLAGS := $(subst -fvisibility=hidden,,$(XCFLAGS))

MINIOBJS += version.$(OBJEXT)
DLDOBJS += $(RUBY_VERSION_SO)
LIBRUBYARG_SHARED := -lruby_version $(LIBRUBYARG_SHARED)
$(LIBRUBY_SO): COMMONOBJS := $(filter-out version.$(OBJEXT),$(COMMONOBJS))
$(LIBRUBY_A): COMMONOBJS := $(sort version.$(OBJEXT) $(COMMONOBJS))

$(LIBRUBY_SO): $(RUBY_VERSION_SO)

$(RUBY_VERSION_SO): version.$(OBJEXT)
	$(ECHO) linking shared-library $@
	$(LDSHARED) $(RUBY_VERSION_DLDFLAGS) version.$(OBJEXT) $(OUTFLAG)$@
	-$(Q) $(MINIRUBY) -e 'ARGV.each{|link|' \
		-e   'File.delete link rescue nil' \
		-e   'File.symlink "$(RUBY_VERSION_SO)", link' \
		-e '}' \
		$(subst ruby,ruby_version,$(LIBRUBY_ALIASES)) || true

endif
