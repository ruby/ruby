# -*- makefile-gmake -*-
gnumake = yes

CHECK_TARGETS := exam love check%
TEST_TARGETS := $(filter check test check% test% btest%,$(MAKECMDGOALS))
TEST_TARGETS += $(subst check,test-all,$(patsubst check-%,test-%,$(TEST_TARGETS)))
TEST_TARGETS := $(patsubst test-%,yes-test-%,$(patsubst btest-%,yes-btest-%,$(TEST_TARGETS)))
TEST_DEPENDS := $(if $(TEST_TARGETS),$(filter all main exts,$(MAKECMDGOALS)))
TEST_DEPENDS += $(if $(filter $(CHECK_TARGETS),$(MAKECMDGOALS)),main)
TEST_DEPENDS += $(if $(filter main,$(TEST_DEPENDS)),$(if $(filter all,$(INSTALLDOC)),docs))

ifneq ($(filter -O0 -Od,$(optflags)),)
override XCFLAGS := $(filter-out -D_FORTIFY_SOURCE=%,$(XCFLAGS))
endif

ifeq ($(if $(filter all main exts enc trans libencs libenc libtrans \
		    prog program ruby ruby$(EXEEXT) \
		    wprogram rubyw rubyw$(EXEEXT) \
		    miniruby$(EXEEXT) mini,\
	     $(MAKECMDGOALS)),,$(MAKECMDGOALS)),)
-include $(SHOWFLAGS)
endif

ifneq ($(filter universal-%,$(arch)),)
define archcmd
%.$(1).S: %.c
	@$$(ECHO) translating $$< with $(2)
	$$(Q) $$(CC) $$(CFLAGS_NO_ARCH) $(2) $$(XCFLAGS) $$(CPPFLAGS) $$(COUTFLAG)$$@ -S $$<

%.S: %.$(1).S

%.$(1).i: %.c
	@$$(ECHO) preprocessing $$< with $(2)
	$$(Q) $$(CPP) $$(warnflags) $(2) $$(XCFLAGS) $$(CPPFLAGS) $$(COUTFLAG)$$@ -E $$< > $$@

%.i: %.$(1).i
endef

$(foreach arch,$(filter -arch=%,$(subst -arch ,-arch=,$(ARCH_FLAG))),\
	$(eval $(call archcmd,$(patsubst -arch=%,%,$(value arch)),$(patsubst -arch=%,-arch %,$(value arch)))))
endif

ifneq ($(filter $(CHECK_TARGETS) test,$(MAKECMDGOALS)),)
yes-test-basic: $(TEST_DEPENDS) yes-test-knownbug
yes-test-knownbug: $(TEST_DEPENDS) yes-btest-ruby
yes-btest-ruby: $(TEST_DEPENDS)
endif
ifneq ($(filter $(CHECK_TARGETS),$(MAKECMDGOALS)) $(filter yes-test-all,$(TEST_TARGETS)),)
yes-test-testframework yes-test-almost yes-test-ruby: $(filter-out %test-all %test-ruby check%,$(TEST_TARGETS)) \
	yes-test-basic
endif
ifneq ($(filter $(CHECK_TARGETS),$(MAKECMDGOALS))$(if $(filter test-all,$(MAKECMDGOALS)),$(filter test-knownbug,$(MAKECMDGOALS))),)
yes-test-testframework yes-test-almost yes-test-ruby: yes-test-knownbug
yes-test-almost: yes-test-testframework
endif

$(TEST_TARGETS): $(TEST_DEPENDS)

ifneq ($(if $(filter install,$(MAKECMDGOALS)),$(filter uninstall,$(MAKECMDGOALS))),)
install-targets := $(filter install uninstall,$(MAKECMDGOALS))
$(word 1,$(install-targets)): $(word 0,$(install-targets))
endif

ifneq ($(filter reinstall,$(MAKECMDGOALS)),)
install-prereq: uninstall
uninstall sudo-precheck: all $(if $(filter all,$(INSTALLDOC)),docs)
endif

ifneq ($(filter exam,$(MAKECMDGOALS)),)
test-rubyspec: check
yes-test-all no-test-all: test
endif

ifneq ($(filter love,$(MAKECMDGOALS)),)
showflags: up
sudo-precheck: test yes-test-testframework no-test-testframework
install-prereq: sudo-precheck
yes-test-all no-test-all: install
yes-test-almost no-test-almost: install
endif

$(srcdir)/missing/des_tables.c: $(srcdir)/missing/crypt.c
ifeq ($(if $(filter yes,$(CROSS_COMPILING)),,$(CC)),)
	touch $@
else
	@$(ECHO) building make_des_table
	$(CC) $(CPPFLAGS) -DDUMP $(LDFLAGS) $(XLDFLAGS) $(LIBS) -omake_des_table $(srcdir)/missing/crypt.c
	@[ -x ./make_des_table ]
	@$(ECHO) generating $@
	$(Q) $(MAKEDIRS) $(@D)
	$(Q) ./make_des_table > $@.new
	$(Q) mv $@.new $@
	$(Q) $(RMALL) make_des_table*
endif

STUBPROGRAM = rubystub$(EXEEXT)
IGNOREDPATTERNS = %~ .% %.orig %.rej \#%\#
SCRIPTBINDIR := $(if $(EXEEXT),,exec/)
SCRIPTPROGRAMS = $(addprefix $(SCRIPTBINDIR),$(addsuffix $(EXEEXT),$(filter-out $(IGNOREDPATTERNS),$(notdir $(wildcard $(srcdir)/bin/*)))))

stub: $(STUBPROGRAM)
scriptbin: $(SCRIPTPROGRAMS)
ifneq ($(STUBPROGRAM),rubystub)
rubystub: $(STUBPROGRAM)
endif

$(SCRIPTPROGRAMS): $(STUBPROGRAM)

$(STUBPROGRAM): rubystub.$(OBJEXT) $(LIBRUBY) $(MAINOBJ) $(OBJS) $(EXTOBJS) $(SETUP) $(PREP)

rubystub$(EXEEXT):
	@rm -f $@
	$(ECHO) linking $@
	$(Q) $(PURIFY) $(CC) $(LDFLAGS) $(XLDFLAGS) rubystub.$(OBJEXT) $(EXTOBJS) $(LIBRUBYARG) $(MAINLIBS) $(LIBS) $(EXTLIBS) $(OUTFLAG)$@
	$(Q) $(POSTLINK)
	$(if $(STRIP),$(Q) $(STRIP) $@)

$(SCRIPTBINDIR)%$(EXEEXT): bin/% $(STUBPROGRAM) \
			   $(if $(SCRIPTBINDIR),$(TIMESTAMPDIR)/.exec.time)
	$(ECHO) generating $@
	$(Q) { cat $(STUBPROGRAM); echo; sed -e '1{' -e '/^#!.*ruby/!i\' -e '#!/bin/ruby' -e '}' $<; } > $@
	$(Q) chmod +x $@
	$(Q) $(POSTLINK)

$(TIMESTAMPDIR)/.exec.time:
	$(Q) mkdir exec
	$(Q) exit > $@
