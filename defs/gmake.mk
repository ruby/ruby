# -*- mode: makefile-gmake; indent-tabs-mode: t -*-

reconfig config.status: export MAKE:=$(MAKE)
override gnumake_recursive := $(if $(findstring n,$(firstword $(MFLAGS))),,+)
override mflags := $(filter-out -j%,$(MFLAGS))
MSPECOPT += $(if $(filter -j%,$(MFLAGS)),-j)
nproc = $(subst -j,,$(filter -j%,$(MFLAGS)))

ifeq ($(GITHUB_ACTIONS),true)
override ACTIONS_GROUP = @echo "\#\#[group]$(patsubst yes-%,%,$@)"
override ACTIONS_ENDGROUP = @echo "\#\#[endgroup]"
endif

ifneq ($(filter %darwin%,$(arch)),)
INSTRUBY_ENV += SDKROOT=/
endif
INSTRUBY_ARGS += --gnumake

CHECK_TARGETS := great exam love check test check% test% btest%
# expand test targets, and those dependents
TEST_TARGETS := $(filter $(CHECK_TARGETS),$(MAKECMDGOALS))
TEST_DEPENDS := $(filter-out commit $(TEST_TARGETS),$(MAKECMDGOALS))
TEST_TARGETS := $(patsubst great,exam,$(TEST_TARGETS))
TEST_DEPENDS := $(filter-out great $(TEST_TARGETS),$(TEST_DEPENDS))
TEST_TARGETS := $(patsubst exam,check,$(TEST_TARGETS))
TEST_TARGETS := $(patsubst check,test-spec test-all test-tool test-short,$(TEST_TARGETS))
TEST_TARGETS := $(patsubst test-rubyspec,test-spec,$(TEST_TARGETS))
TEST_DEPENDS := $(filter-out exam check test-spec $(TEST_TARGETS),$(TEST_DEPENDS))
TEST_TARGETS := $(patsubst love,check,$(TEST_TARGETS))
TEST_DEPENDS := $(filter-out love $(TEST_TARGETS),$(TEST_DEPENDS))
TEST_TARGETS := $(patsubst test-almost,test-all,$(patsubst check-%,test test-%,$(TEST_TARGETS)))
TEST_DEPENDS := $(filter-out test-all $(TEST_TARGETS),$(TEST_DEPENDS))
TEST_TARGETS := $(patsubst test,test-short,$(TEST_TARGETS))
TEST_DEPENDS := $(filter-out test $(TEST_TARGETS),$(TEST_DEPENDS))
TEST_TARGETS := $(patsubst test-short,btest-ruby test-knownbug test-basic,$(TEST_TARGETS))
TEST_TARGETS := $(patsubst test-bundled-gems,test-bundled-gems-run,$(TEST_TARGETS))
TEST_TARGETS := $(patsubst test-bundled-gems-run,test-bundled-gems-run $(PREPARE_BUNDLED_GEMS),$(TEST_TARGETS))
TEST_TARGETS := $(patsubst test-bundled-gems-prepare,test-bundled-gems-prepare $(PRECHECK_BUNDLED_GEMS) test-bundled-gems-fetch,$(TEST_TARGETS))
TEST_DEPENDS := $(filter-out test-short $(TEST_TARGETS),$(TEST_DEPENDS))
TEST_DEPENDS += $(if $(filter great exam love check,$(MAKECMDGOALS)),all exts)

in-srcdir := $(if $(filter-out .,$(srcdir)),$(CHDIR) $(srcdir) &&)

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
	test-testframework test-tool test-ruby test-all \
	test-spec test-bundler-prepare test-bundler test-bundler-parallel \
	test-bundled-gems-precheck test-bundled-gems-fetch \
	test-bundled-gems-prepare test-bundled-gems-run \
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
endif
yes-test-bundler-parallel: PARALLELRSPECOPTS += $(if $(nproc),-n$(shell expr $(nproc) + $(nproc) / 2))

# Cross reference needs to parse all files at once
love install reinstall: RDOCFLAGS = --force-update

ifneq ($(if $(filter -flto%,$(CFLAGS)),$(subst darwin,,$(arch)),$(arch)),$(arch))
override EXE_LDFLAGS = $(filter-out -g%,$(LDFLAGS))
endif

$(srcdir)/missing/des_tables.c: $(srcdir)/missing/crypt.c
ifeq ($(if $(filter yes,$(CROSS_COMPILING)),,$(CC)),)
	touch $@
else
	@$(ECHO) building make_des_table
	$(CC) $(INCFLAGS) $(CPPFLAGS) -DDUMP $(EXE_LDFLAGS) $(XLDFLAGS) $(LIBS) -omake_des_table $(srcdir)/missing/crypt.c
	@[ -x ./make_des_table ]
	@$(ECHO) generating $@
	$(Q) $(MAKEDIRS) $(@D)
	$(Q) ./make_des_table > $@.new
	$(Q) mv $@.new $@
	$(Q) $(RMALL) make_des_table*
endif

config.status: $(wildcard config.cache)

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
	$(Q) $(PURIFY) $(CC) $(EXE_LDFLAGS) $(XLDFLAGS) rubystub.$(OBJEXT) $(EXTOBJS) $(LIBRUBYARG) $(MAINLIBS) $(LIBS) $(EXTLIBS) $(OUTFLAG)$@
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
commit: $(if $(filter commit,$(MAKECMDGOALS)),$(filter-out commit,$(MAKECMDGOALS))) up
	@$(BASERUBY) -C "$(srcdir)" -I./tool/lib -rvcs -e 'VCS.detect(".").commit'
	+$(Q) \
	{ \
	  $(in-srcdir) \
	  exec sed -f tool/prereq.status defs/gmake.mk template/Makefile.in common.mk; \
	} | \
	$(MAKE) $(mflags) Q=$(Q) ECHO=$(ECHO) srcdir="$(srcdir)" srcs_vpath="" CHDIR="$(CHDIR)" \
		BOOTSTRAPRUBY="$(BOOTSTRAPRUBY)" MINIRUBY="$(BASERUBY)" BASERUBY="$(BASERUBY)" \
		VCSUP="" ENC_MK=.top-enc.mk REVISION_FORCE=PHONY CONFIGURE="$(CONFIGURE)" -f - \
		update-src srcs all-incs

GITHUB_RUBY_URL = https://github.com/ruby/ruby
PR =

COMMIT_GPG_SIGN = $(shell $(GIT) -C "$(srcdir)" config commit.gpgsign)
REMOTE_GITHUB_URL = $(shell $(GIT) -C "$(srcdir)" config remote.github.url)
COMMITS_NOTES = commits

.PHONY: fetch-github
fetch-github:
	$(call fetch-github,$(PR))

define fetch-github
	$(if $(1),,\
	  echo "usage:"; echo "  make $@ PR=1234"; \
	  exit 1; \
	)
	$(eval REMOTE_GITHUB_URL := $(REMOTE_GITHUB_URL))
	$(if $(REMOTE_GITHUB_URL),,
	  echo adding $(GITHUB_RUBY_URL) as remote github
	  $(GIT) -C "$(srcdir)" remote add github $(GITHUB_RUBY_URL)
	  $(GIT) -C "$(srcdir)" config --add remote.github.fetch +refs/notes/$(COMMITS_NOTES):refs/notes/$(COMMITS_NOTES)
	  $(eval REMOTE_GITHUB_URL := $(GITHUB_RUBY_URL))
	)
	$(if $(shell $(GIT) -C "$(srcdir)" rev-parse "github/pull/$(1)/head" -- 2> /dev/null),
	    $(GIT) -C "$(srcdir)" branch -f "gh-$(1)" "github/pull/$(1)/head",
	    $(GIT) -C "$(srcdir)" fetch -f github "pull/$(1)/head:gh-$(1)"
	)
endef

.PHONY: checkout-github
checkout-github: fetch-github
	$(GIT) -C "$(srcdir)" checkout "gh-$(PR)"

.PHONY: update-github
update-github: fetch-github
	$(eval PULL_REQUEST_API := https://api.github.com/repos/ruby/ruby/pulls/$(PR))
	$(eval PULL_REQUEST_FORK_BRANCH := $(shell \
	  curl -s $(if $(GITHUB_TOKEN),-H "Authorization: bearer $(GITHUB_TOKEN)") $(PULL_REQUEST_API) | \
	  $(BASERUBY) -rjson -e 'JSON.parse(STDIN.read)["head"].tap { |h| print "#{h["repo"]["full_name"]} #{h["ref"]}" }' \
	))
	$(eval FORK_REPO := $(word 1,$(PULL_REQUEST_FORK_BRANCH)))
	$(eval PR_BRANCH := $(word 2,$(PULL_REQUEST_FORK_BRANCH)))

	$(eval GITHUB_UPDATE_WORKTREE := $(shell mktemp -d "$(srcdir)/gh-$(PR)-XXXXXX"))
	$(GIT) -C "$(srcdir)" worktree add $(notdir $(GITHUB_UPDATE_WORKTREE)) "gh-$(PR)"
	$(GIT) -C "$(GITHUB_UPDATE_WORKTREE)" merge master --no-edit
	@$(BASERUBY) -e 'print "Are you sure to push this to PR=$(PR)? [Y/n]: "; exit(gets.chomp != "n")'
	$(GIT) -C "$(srcdir)" remote add fork-$(PR) git@github.com:$(FORK_REPO).git
	$(GIT) -C "$(GITHUB_UPDATE_WORKTREE)" push fork-$(PR) gh-$(PR):$(PR_BRANCH)
	$(GIT) -C "$(srcdir)" remote rm fork-$(PR)
	$(GIT) -C "$(srcdir)" worktree remove $(notdir $(GITHUB_UPDATE_WORKTREE))
	$(GIT) -C "$(srcdir)" branch -D gh-$(PR)

.PHONY: pull-github
pull-github: fetch-github
	$(call pull-github,$(PR))

define pull-github
	$(eval GITHUB_MERGE_BASE := $(shell $(GIT) -C "$(srcdir)" log -1 --format=format:%H))
	$(eval GITHUB_MERGE_BRANCH := $(shell $(GIT) -C "$(srcdir)" symbolic-ref --short HEAD))
	$(eval GITHUB_MERGE_WORKTREE := $(shell mktemp -d "$(srcdir)/gh-$(1)-XXXXXX"))
	$(GIT) -C "$(srcdir)" worktree prune
	$(GIT) -C "$(srcdir)" worktree add $(notdir $(GITHUB_MERGE_WORKTREE)) "gh-$(1)"
	$(GIT) -C "$(GITHUB_MERGE_WORKTREE)" rebase $(GITHUB_MERGE_BRANCH)
	$(eval COMMIT_GPG_SIGN := $(COMMIT_GPG_SIGN))
	$(if $(filter true,$(COMMIT_GPG_SIGN)), \
	  $(GIT) -C "$(GITHUB_MERGE_WORKTREE)" rebase --exec "$(GIT) commit --amend --no-edit -S" "$(GITHUB_MERGE_BASE)"; \
	)
	$(GIT) -C "$(GITHUB_MERGE_WORKTREE)" rebase --exec "$(GIT) notes add --message 'Merged: $(GITHUB_RUBY_URL)/pull/$(1)'" "$(GITHUB_MERGE_BASE)"
endef

.PHONY: fetch-github-%
fetch-github-%:
	$(call fetch-github,$*)

.PHONY: checkout-github-%
checkout-github-%: fetch-github-%
	$(GIT) -C "$(srcdir)" checkout "gh-$*"

.PHONY: pr-% pull-github-%
pr-% pull-github-%: fetch-github-%
	$(call pull-github,$*)

HELP_EXTRA_TASKS = \
	"  checkout-github:     checkout GitHub Pull Request [PR=1234]" \
	"  pull-github:         rebase GitHub Pull Request to new worktree [PR=1234]" \
	"  update-github:       merge master branch and push it to Pull Request [PR=1234]" \
	""

extract-gems: $(HAVE_BASERUBY:yes=update-gems)

bundled-gems := $(shell sed '/^[ 	]*\#/d;/^[ 	]*$$/d;s/[ 	][ 	]*/-/;s/[ 	].*//' $(srcdir)/gems/bundled_gems)

update-gems: | $(patsubst %,gems/%.gem,$(bundled-gems))

test-bundler-precheck: | $(srcdir)/.bundle/cache

$(srcdir)/.bundle/cache:
	$(MAKEDIRS) $(@D) $(CACHE_DIR)
	$(LN_S) ../.downloaded-cache $@

gems/%.gem:
	$(ECHO) Downloading bundled gem $*...
	$(Q) $(BASERUBY) -C "$(srcdir)" \
	    -I./tool -rdownloader \
	    -e 'gem = "$(@F)"' \
	    -e 'old = Dir.glob("gems/"+gem.sub(/-[^-]*$$/, "-*.gem"))' \
	    -e 'Downloader::RubyGems.download(gem, "gems", nil) and' \
	    -e '(old.delete("gems/#{gem}"); !old.empty?) and' \
	    -e 'File.unlink(*old) and' \
	    -e 'FileUtils.rm_rf(old.map{'"|n|"'n.chomp(".gem")})'

ifeq (,)
extract-gems: extract-gems-sequential
else
extract-gems: | $(patsubst %,.bundle/gems/%,$(bundled-gems))

.bundle/gems/%: gems/%.gem | .bundle/gems
	$(ECHO) Extracting bundle gem $*...
	$(Q) $(BASERUBY) -C "$(srcdir)" \
	    -Itool/lib -rbundled_gem \
	    -e 'BundledGem.unpack("gems/$(@F).gem", ".bundle")'
	$(RMALL) "$(srcdir)/$(@:.gem=)/".git*

$(srcdir)/.bundle/gems:
	$(MAKEDIRS) $@
endif

ifneq ($(filter update-bundled_gems refresh-gems,$(MAKECMDGOALS)),)
update-gems: update-bundled_gems
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

ifeq ($(if $(wildcard $(filter-out .,$(UNICODE_FILES) $(UNICODE_PROPERTY_FILES))),,\
	   $(wildcard $(srcdir)/lib/unicode_normalize/tables.rb)),)
# Needs the dependency when any Unicode data file exists, or
# normalization tables script doesn't.  Otherwise, when the target
# only exists, use it as-is.
.PHONY: $(UNICODE_SRC_DATA_DIR)/.unicode-tables.time
UNICODE_TABLES_TIMESTAMP =
$(UNICODE_SRC_DATA_DIR)/.unicode-tables.time: \
	$(UNICODE_FILES) $(UNICODE_PROPERTY_FILES)
endif

ifeq ($(wildcard $(srcdir)/revision.h),)
REVISION_IN_HEADER := none
REVISION_LATEST := update
else
REVISION_IN_HEADER := $(shell sed -n 's/^\#define RUBY_FULL_REVISION "\(.*\)"/\1/p' $(srcdir)/revision.h 2>/dev/null)
REVISION_LATEST := $(shell $(CHDIR) $(srcdir) && $(GIT) log -1 --format=%H 2>/dev/null)
endif
ifneq ($(REVISION_IN_HEADER),$(REVISION_LATEST))
# GNU make treat the target as unmodified when its dependents get
# updated but it is not updated, while others may not.
$(srcdir)/revision.h: $(REVISION_H)
endif

# Query on the generated rdoc
#
#   $ make rdoc:Integer#+
rdoc\:%: PHONY
	$(Q)$(RUNRUBY) $(srcdir)/libexec/ri --no-standard-docs --doc-dir=$(RDOCOUT) $(patsubst rdoc:%,%,$@)

test_%.rb test/%: programs PHONY
	$(Q)$(exec) $(RUNRUBY) "$(TESTSDIR)/runner.rb" --ruby="$(RUNRUBY)" $(TEST_EXCLUDES) $(TESTOPTS) -- $(patsubst test/%,%,$@)

spec/bundler/%: PHONY
	$(Q)$(exec) $(XRUBY) -C $(srcdir) -Ispec/bundler .bundle/bin/rspec --require spec_helper $(RSPECOPTS) $@

spec/bundler: test-bundler-parallel
	$(Q)$(NULLCMD)

# workaround to avoid matching non ruby files with "spec/%/" under GNU make 3.81
spec/%_spec.c:
	$(empty)
$(srcdir)/$(RUBYSPEC_CAPIEXT)/rubyspec.h:
	$(empty)

benchmark/%: miniruby$(EXEEXT) update-benchmark-driver PHONY
	$(Q)$(BASERUBY) -rrubygems -I$(srcdir)/benchmark/lib $(srcdir)/benchmark/benchmark-driver/exe/benchmark-driver \
	            --executables="compare-ruby::$(COMPARE_RUBY) -I$(EXTOUT)/common --disable-gem" \
	            --executables="built-ruby::$(BENCH_RUBY) --disable-gem" \
	            $(srcdir)/$@ $(BENCH_OPTS) $(OPTS)

clean-srcs-ext::
	$(Q)$(RM) $(patsubst $(srcdir)/%,%,$(EXT_SRCS))

clean-srcs-extra::
	$(Q)$(RM) $(patsubst $(srcdir)/%,%,$(EXTRA_SRCS))

ifneq ($(filter $(VCS),git),)
update-src::
	@$(BASERUBY) $(tooldir)/lib/colorize.rb pass "Latest commit hash = $(shell $(filter-out svn,$(VCS)) -C $(srcdir) rev-parse --short=10 HEAD)"
endif

# Update dependencies and commit the updates to the current branch.
update-deps:
	$(eval update_deps := $(shell date +update-deps-%Y%m%d))
	$(eval deps_dir := $(shell mktemp -d)/$(update_deps))
	$(eval GIT_DIR := $(shell $(GIT) -C $(srcdir) rev-parse --absolute-git-dir))
	$(GIT) --git-dir=$(GIT_DIR) worktree add $(deps_dir)
	cp $(tooldir)/config.guess $(tooldir)/config.sub $(deps_dir)/tool
	[ -f config.status ] && cp config.status $(deps_dir)
	cd $(deps_dir) && autoconf && \
	exec ./configure -q -C --enable-load-relative --disable-install-doc --disable-rubygems 'optflags=-O0' 'debugflags=-save-temps=obj -g'
	$(RUNRUBY) -C $(deps_dir) tool/update-deps --fix
	$(GIT) -C $(deps_dir) diff --no-ext-diff --ignore-submodules --exit-code || \
	    $(GIT) -C $(deps_dir) commit --all --message='Update dependencies'
	$(GIT) --git-dir=$(GIT_DIR) worktree remove $(deps_dir)
	$(RMDIR) $(dir $(deps_dir))
	$(GIT) --git-dir=$(GIT_DIR) merge --no-edit --ff-only $(update_deps)
	$(GIT) --git-dir=$(GIT_DIR) branch --delete $(update_deps)

# order-only-prerequisites doesn't work for $(RUBYSPEC_CAPIEXT)
# because the same named directory exists in the source tree.
$(RUBYSPEC_CAPIEXT)/%.$(DLEXT): $(srcdir)/$(RUBYSPEC_CAPIEXT)/%.c $(srcdir)/$(RUBYSPEC_CAPIEXT)/rubyspec.h $(RUBY_H_INCLUDES) $(LIBRUBY)
	$(ECHO) building $@
	$(Q) $(MAKEDIRS) $(@D)
	$(Q) $(DLDSHARED) $(XDLDFLAGS) $(XLDFLAGS) $(LDFLAGS) $(INCFLAGS) $(CPPFLAGS) $(OUTFLAG)$@ $< $(LIBRUBYARG)
	$(Q) $(RMALL) $@.*

rubyspec-capiext: $(patsubst %.c,$(RUBYSPEC_CAPIEXT)/%.$(DLEXT),$(notdir $(wildcard $(srcdir)/$(RUBYSPEC_CAPIEXT)/*.c)))
	@ $(NULLCMD)

ifeq ($(ENABLE_SHARED),yes)
exts: rubyspec-capiext
endif

spec/%/ spec/%_spec.rb: programs exts PHONY
	+$(RUNRUBY) -r./$(arch)-fake $(srcdir)/spec/mspec/bin/mspec-run -B $(srcdir)/spec/default.mspec $(SPECOPTS) $(patsubst %,$(srcdir)/%,$@)

ruby.pc: $(filter-out ruby.pc,$(ruby_pc))
