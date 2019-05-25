# -*- mode: makefile-gmake; indent-tabs-mode: t -*-

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
TEST_TARGETS := $(patsubst exam,check,$(TEST_TARGETS))
TEST_TARGETS := $(patsubst check,test-spec test-all,$(TEST_TARGETS))
TEST_TARGETS := $(patsubst test-rubyspec,test-spec,$(TEST_TARGETS))
TEST_DEPENDS := $(filter-out exam check test-spec $(TEST_TARGETS),$(TEST_DEPENDS))
TEST_TARGETS := $(patsubst love,check,$(TEST_TARGETS))
TEST_DEPENDS := $(filter-out love $(TEST_TARGETS),$(TEST_DEPENDS))
TEST_TARGETS := $(patsubst test-all,test test-testframework test-almost,$(patsubst check-%,test test-%,$(TEST_TARGETS)))
TEST_DEPENDS := $(filter-out test-all $(TEST_TARGETS),$(TEST_DEPENDS))
TEST_TARGETS := $(patsubst test,test-short,$(TEST_TARGETS))
TEST_DEPENDS := $(filter-out test $(TEST_TARGETS),$(TEST_DEPENDS))
TEST_TARGETS := $(patsubst test-short,btest-ruby test-knownbug test-basic,$(TEST_TARGETS))
TEST_DEPENDS := $(filter-out test-short $(TEST_TARGETS),$(TEST_DEPENDS))
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

$(foreach arch,$(arch_flags),\
	$(eval $(call archcmd,$(patsubst -arch=%,%,$(value arch)),$(patsubst -arch=%,-arch %,$(value arch)))))
endif

.PHONY: $(addprefix yes-,$(TEST_TARGETS))

ifneq ($(filter-out btest%,$(TEST_TARGETS)),)
$(addprefix yes-,$(TEST_TARGETS)): $(TEST_DEPENDS)
endif

ORDERED_TEST_TARGETS := $(filter $(TEST_TARGETS), \
	btest-ruby test-knownbug test-basic \
	test-testframework test-ruby test-almost test-all \
	test-spec test-bundler-prepare test-bundler \
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
ifneq ($(filter love install reinstall,$(MAKECMDGOALS)),)
# Cross referece needs to parse all files at once
RDOCFLAGS = --force-update
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
SCRIPTPROGRAMS = $(addprefix $(SCRIPTBINDIR),$(addsuffix $(EXEEXT),$(filter-out $(IGNOREDPATTERNS),$(notdir $(wildcard $(srcdir)/libexec/*)))))

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
	+$(Q) \
	{ \
	  $(CHDIR) "$(srcdir)"; \
	  sed 's/^@.*@$$//;s/@[A-Za-z_][A-Za-z_0-9]*@//g;/^all-incs:/d' defs/gmake.mk Makefile.in; \
	  sed 's/{[.;]*$$([a-zA-Z0-9_]*)}//g' common.mk; \
	} | \
	$(MAKE) $(mflags) Q=$(Q) ECHO=$(ECHO) srcdir="$(srcdir)" srcs_vpath="" CHDIR="$(CHDIR)" \
		BOOTSTRAPRUBY="$(BOOTSTRAPRUBY)" MINIRUBY="$(BASERUBY)" BASERUBY="$(BASERUBY)" \
		VCSUP="" ENC_MK=.top-enc.mk REVISION_FORCE=PHONY CONFIGURE="$(CONFIGURE)" -f - \
		update-src srcs all-incs

GITHUB_RUBY_URL = https://github.com/ruby/ruby
PR =

COMMIT_GPG_SIGN = $(shell git -C "$(srcdir)" config commit.gpgsign)
REMOTE_GITHUB_URL = $(shell git -C "$(srcdir)" config remote.github.url)

.PHONY: fetch-github
fetch-github:
	$(call fetch-github,$(PR))

define fetch-github
	$(if $(1),,\
	  echo "usage:"; echo "  make $@ PR=1234"; \
	  exit 1; \
	)
	$(eval REMOTE_GITHUB_URL := $(REMOTE_GITHUB_URL))
	$(if $(REMOTE_GITHUB_URL),, \
	  echo adding $(GITHUB_RUBY_URL) as remote github; \
	  git -C "$(srcdir)" remote add github $(GITHUB_RUBY_URL); \
	  $(eval REMOTE_GITHUB_URL := $(GITHUB_RUBY_URL)) \
	)
	git -C "$(srcdir)" fetch -f github "pull/$(1)/head:gh-$(1)"
endef

.PHONY: checkout-github
checkout-github: fetch-github
	git -C "$(srcdir)" checkout "gh-$(PR)"

.PHONY: merge-github
merge-github: fetch-github
	$(call merge-github,$(PR))

define merge-github
	$(eval GITHUB_MERGE_BASE := $(shell git -C "$(srcdir)" log -1 --format=format:%H))
	$(eval GITHUB_MERGE_BRANCH := $(shell git -C "$(srcdir)" symbolic-ref --short HEAD))
	$(eval GITHUB_MERGE_WORKTREE := $(shell mktemp -d "$(srcdir)/gh-$(1)-XXXXXX"))
	git -C "$(srcdir)" worktree add $(notdir $(GITHUB_MERGE_WORKTREE)) "gh-$(1)"
	git -C "$(GITHUB_MERGE_WORKTREE)" rebase $(GITHUB_MERGE_BRANCH)
	git -C "$(srcdir)" worktree remove $(notdir $(GITHUB_MERGE_WORKTREE))
	git -C "$(srcdir)" merge --ff-only "gh-$(1)"
	git -C "$(srcdir)" branch -D "gh-$(1)"
	git -C "$(srcdir)" filter-branch -f \
	  --msg-filter 'cat && echo && echo "Closes: $(GITHUB_RUBY_URL)/pull/$(1)"' \
	  -- "$(GITHUB_MERGE_BASE)..@"
	$(eval COMMIT_GPG_SIGN := $(COMMIT_GPG_SIGN))
	$(if $(filter true,$(COMMIT_GPG_SIGN)), \
	  git -C "$(srcdir)" rebase --exec "git commit --amend --no-edit -S" "$(GITHUB_MERGE_BASE)"; \
	)
endef

fetch-github-%:
	$(call fetch-github,$*)

pr-% merge-github-%: fetch-github-%
	$(call merge-github,$*)

HELP_EXTRA_TASKS = \
	"  checkout-github:     checkout GitHub Pull Request [PR=1234]" \
	"  merge-github:        merge GitHub Pull Request to current HEAD [PR=1234]" \
	""

ifeq ($(words $(filter update-gems extract-gems,$(MAKECMDGOALS))),2)
extract-gems: update-gems
endif

ifeq ($(filter 0 1,$(words $(arch_flags))),)
$(foreach x,$(patsubst -arch=%,%,$(arch_flags)), \
	  $(eval $$(MJIT_HEADER:.h=)-$(value x).h \
		 $$(MJIT_MIN_HEADER:.h=)-$(value x).h \
		 $$(TIMESTAMPDIR)/$$(MJIT_HEADER:.h=)-$(value x).time \
		 : ARCH_FLAG := -arch $(value x)))

$(foreach x,$(patsubst -arch=%,%,$(arch_flags)), \
	$(eval $$(MJIT_HEADER:.h=)-$(value x).h: \
		$$(TIMESTAMPDIR)/$$(MJIT_HEADER:.h=)-$(value x).time))

mjit_min_headers := $(patsubst -arch=%,$(MJIT_MIN_HEADER:.h=-%.h),$(arch_flags))
$(MJIT_MIN_HEADER): $(mjit_min_headers) $(PREP)
	@ set -e; set $(patsubst -arch=%,%,$(arch_flags)); \
	cd $(@D); h=$(@F:.h=); \
	exec > $(@F).new; \
	echo '#if 0'; \
	for arch; do\
	  echo "#elif defined __$${arch}__"; \
	  echo "# include \"$$h-$$arch.h\""; \
	done; \
	echo "#else"; echo "# error unsupported platform"; echo "#endif"
	$(IFCHANGE) $@ $@.new
	$(Q) $(MAKEDIRS) $(MJIT_HEADER_INSTALL_DIR)
	$(Q) $(MAKE_LINK) $@ $(MJIT_HEADER_INSTALL_DIR)/$(@F)

endif

ifeq ($(if $(wildcard $(UNICODE_FILES) $(UNICODE_PROPERTY_FILES)),,\
	   $(wildcard $(srcdir)/lib/unicode_normalize/tables.rb)),)
# Needs the dependency when any Unicode data file exists, or
# normalization tables script doesn't.  Otherwise, when the target
# only exists, use it as-is.
.PHONY: $(UNICODE_SRC_DATA_DIR)/.unicode-tables.time
UNICODE_TABLES_TIMESTAMP =
$(UNICODE_SRC_DATA_DIR)/.unicode-tables.time: \
	$(UNICODE_FILES) $(UNICODE_PROPERTY_FILES)
endif

# GNU make treat the target as unmodified when its dependents get
# updated but it is not updated, while others may not.
$(srcdir)/revision.h: $(REVISION_H)

# Query on the generated rdoc
#
#   $ make rdoc:Integer#+
rdoc\:%: PHONY
	$(Q)$(RUNRUBY) $(srcdir)/libexec/ri --no-standard-docs --doc-dir=$(RDOCOUT) $(patsubst rdoc:%,%,$@)

test_%.rb test/%: programs PHONY
	+$(Q)$(exec) $(RUNRUBY) "$(srcdir)/test/runner.rb" --ruby="$(RUNRUBY)" $(TEST_EXCLUDES) $(TESTOPTS) -- $(patsubst test/%,%,$@)

clean-srcs-ext::
	$(Q)$(RM) $(patsubst $(srcdir)/%,%,$(EXT_SRCS))

clean-srcs-extra::
	$(Q)$(RM) $(patsubst $(srcdir)/%,%,$(EXTRA_SRCS))

ifneq ($(filter $(VCS),git),)
update-src::
	@$(BASERUBY) $(srcdir)/tool/colorize.rb pass "Latest commit hash = $(shell $(filter-out svn,$(VCS)) -C $(srcdir) rev-parse --short=10 HEAD)"
endif
