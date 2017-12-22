# -*- makefile-gmake -*-
gnumake = yes
override gnumake_recursive := $(if $(findstring n,$(firstword $(MFLAGS))),,+)
override mflags := $(filter-out -j%,$(MFLAGS))
MSPECOPT += $(if $(filter -j%,$(MFLAGS)),-j)

CHECK_TARGETS := great exam love check test check% test% btest%
# expand test targets, and those dependents
TEST_TARGETS := $(filter $(CHECK_TARGETS),$(MAKECMDGOALS))
TEST_DEPENDS := $(filter-out commit $(TEST_TARGETS),$(MAKECMDGOALS))
TEST_TARGETS := $(patsubst great,exam,$(TEST_TARGETS))
TEST_DEPENDS := $(filter-out great $(TEST_TARGETS),$(TEST_DEPENDS))
TEST_TARGETS := $(patsubst exam,check test-rubyspec,$(TEST_TARGETS))
TEST_TARGETS := $(patsubst test-rubyspec,test-spec,$(TEST_TARGETS))
TEST_DEPENDS := $(filter-out exam $(TEST_TARGETS),$(TEST_DEPENDS))
TEST_TARGETS := $(patsubst love,check,$(TEST_TARGETS))
TEST_DEPENDS := $(filter-out love $(TEST_TARGETS),$(TEST_DEPENDS))
TEST_TARGETS := $(patsubst check,test test-testframework test-almost,$(patsubst check-%,test test-%,$(TEST_TARGETS)))
TEST_DEPENDS := $(filter-out check $(TEST_TARGETS),$(TEST_DEPENDS))
TEST_TARGETS := $(patsubst test,btest-ruby test-knownbug test-basic,$(TEST_TARGETS))
TEST_DEPENDS := $(filter-out test $(TEST_TARGETS),$(TEST_DEPENDS))
TEST_DEPENDS += $(if $(filter great exam love check,$(MAKECMDGOALS)),all exts)

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

.PHONY: $(addprefix yes-,$(TEST_TARGETS))

ifneq ($(filter-out btest%,$(TEST_TARGETS)),)
$(addprefix yes-,$(TEST_TARGETS)): $(TEST_DEPENDS)
endif

ORDERED_TEST_TARGETS := $(filter $(TEST_TARGETS), \
	btest-ruby test-knownbug test-basic \
	test-testframework test-ruby test-almost test-all \
	test-spec \
	)
prev_test := $(if $(filter test-spec,$(ORDERED_TEST_TARGETS)),test-spec-precheck)
$(foreach test,$(ORDERED_TEST_TARGETS), \
	$(eval yes-$(value test) no-$(value test): $(value prev_test)); \
	$(eval prev_test := $(value test)))

ifneq ($(if $(filter install,$(MAKECMDGOALS)),$(filter uninstall,$(MAKECMDGOALS))),)
install-targets := $(filter install uninstall,$(MAKECMDGOALS))
$(word 1,$(install-targets)): $(word 0,$(install-targets))
endif

ifneq ($(filter reinstall,$(MAKECMDGOALS)),)
install-prereq: uninstall
uninstall sudo-precheck: all $(if $(filter all,$(INSTALLDOC)),docs)
endif

ifneq ($(filter love,$(MAKECMDGOALS)),)
showflags: up
sudo-precheck: test yes-test-testframework no-test-testframework
install-prereq: sudo-precheck
yes-test-all no-test-all: install
yes-test-almost no-test-almost: install
endif
ifneq ($(filter great,$(MAKECMDGOALS)),)
love: test-rubyspec
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

.PHONY: commit
commit: $(if $(filter commit,$(MAKECMDGOALS)),$(filter-out commit,$(MAKECMDGOALS)))
	@$(BASERUBY) -C "$(srcdir)" -I./tool -rvcs -e 'VCS.detect(".").commit'
	$(Q)$(MAKE) $(mflags) Q=$(Q) REVISION_FORCE=PHONY update-src srcs all-incs

ifeq ($(words $(filter update-gems extract-gems,$(MAKECMDGOALS))),2)
extract-gems: update-gems
endif
