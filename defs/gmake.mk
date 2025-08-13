# -*- mode: makefile-gmake; indent-tabs-mode: t -*-

reconfig config.status: export MAKE:=$(MAKE)
export BASERUBY:=$(BASERUBY)
override gnumake_recursive := $(if $(findstring n,$(firstword $(MFLAGS))),,+)
override mflags := $(filter-out -j%,$(MFLAGS))
MSPECOPT += $(if $(filter -j%,$(MFLAGS)),-j)
nproc = $(subst -j,,$(filter -j%,$(MFLAGS)))

ifeq ($(GITHUB_ACTIONS),true)
# 93(bright yellow) is copied from .github/workflows/mingw.yml
override ACTIONS_GROUP = @echo "::group::[93m$(@:yes-%=%)[m"
override ACTIONS_ENDGROUP = @echo "::endgroup::"
endif

ifneq ($(filter darwin%,$(target_os)),)
INSTRUBY_ENV += SDKROOT=
endif
INSTRUBY_ARGS += --gnumake

ifeq ($(DOT_WAIT),)
CHECK_TARGETS := great exam love check test check% test% btest%
# expand test targets, and those dependents
TEST_TARGETS := $(filter $(CHECK_TARGETS),$(MAKECMDGOALS))
TEST_DEPENDS := $(filter-out commit $(TEST_TARGETS),$(MAKECMDGOALS))
TEST_TARGETS := $(patsubst great,exam,$(TEST_TARGETS))
TEST_DEPENDS := $(filter-out great $(TEST_TARGETS),$(TEST_DEPENDS))
TEST_TARGETS := $(patsubst exam,test-bundled-gems test-bundler-parallel check,$(TEST_TARGETS))
TEST_TARGETS := $(patsubst check,test-syntax-suggest test-spec test-all test-tool test-short,$(TEST_TARGETS))
TEST_TARGETS := $(patsubst test-rubyspec,test-spec,$(TEST_TARGETS))
TEST_DEPENDS := $(filter-out exam check test-spec $(TEST_TARGETS),$(TEST_DEPENDS))
TEST_TARGETS := $(patsubst love,check,$(TEST_TARGETS))
TEST_DEPENDS := $(filter-out love $(TEST_TARGETS),$(TEST_DEPENDS))
TEST_TARGETS := $(patsubst test-almost,test-all,$(patsubst check-%,test test-%,$(TEST_TARGETS)))
TEST_DEPENDS := $(filter-out test-all $(TEST_TARGETS),$(TEST_DEPENDS))
TEST_TARGETS := $(patsubst test,test-short,$(TEST_TARGETS))
TEST_DEPENDS := $(filter-out test $(TEST_TARGETS),$(TEST_DEPENDS))
TEST_TARGETS := $(patsubst test-short,btest-ruby test-knownbug test-basic,$(TEST_TARGETS))
TEST_TARGETS := $(patsubst test-basic,test-basic test-leaked-globals,$(TEST_TARGETS))
TEST_TARGETS := $(patsubst test-bundled-gems,test-bundled-gems-spec test-bundled-gems-run,$(TEST_TARGETS))
TEST_TARGETS := $(patsubst test-bundled-gems-run,test-bundled-gems-run $(PREPARE_BUNDLED_GEMS),$(TEST_TARGETS))
TEST_TARGETS := $(patsubst test-bundled-gems-prepare,test-bundled-gems-prepare $(PRECHECK_BUNDLED_GEMS) test-bundled-gems-fetch,$(TEST_TARGETS))
TEST_TARGETS := $(patsubst test-bundler-parallel,test-bundler-parallel $(PREPARE_BUNDLER),$(TEST_TARGETS))
TEST_TARGETS := $(patsubst test-syntax-suggest,test-syntax-suggest $(PREPARE_SYNTAX_SUGGEST),$(TEST_TARGETS))
TEST_DEPENDS := $(filter-out test-short $(TEST_TARGETS),$(TEST_DEPENDS))
TEST_DEPENDS += $(if $(filter great exam love check,$(MAKECMDGOALS)),all exts)
TEST_TARGETS := $(patsubst yes-%,%,$(filter-out no-%,$(TEST_TARGETS)))
endif

in-srcdir := $(if $(filter-out .,$(srcdir)),$(CHDIR) $(srcdir) &&)

ifeq ($(if $(filter all main exts enc trans libencs libenc libtrans \
		    prog program ruby ruby$(EXEEXT) \
		    wprogram rubyw rubyw$(EXEEXT) \
		    miniruby$(EXEEXT) mini,\
	     $(MAKECMDGOALS)),,$(MAKECMDGOALS)),)
-include $(SHOWFLAGS)
endif

ifeq ($(HAVE_BASERUBY):$(HAVE_GIT),yes:yes)
override modified := $(shell $(BASERUBY) -C $(srcdir) tool/file2lastrev.rb --modified='%Y %m %d')
override RUBY_RELEASE_YEAR := $(word 1,$(modified))
override RUBY_RELEASE_MONTH := $(word 2,$(modified))
override RUBY_RELEASE_DAY := $(word 3,$(modified))
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

ifeq ($(DOT_WAIT),)
.PHONY: $(addprefix yes-,$(TEST_TARGETS))

ifneq ($(filter-out btest%,$(TEST_TARGETS)),)
$(addprefix yes-,$(TEST_TARGETS)): $(TEST_DEPENDS)
endif

ORDERED_TEST_TARGETS := $(filter $(TEST_TARGETS), \
	btest-ruby test-knownbug test-leaked-globals test-basic \
	test-testframework test-tool test-ruby test-all \
	test-spec test-syntax-suggest-prepare test-syntax-suggest \
	test-bundler-prepare test-bundler test-bundler-parallel \
	test-bundled-gems-precheck test-bundled-gems-fetch \
	test-bundled-gems-prepare test-bundled-gems-run \
	test-bundled-gems-spec \
	)

# grep ^yes-test-.*-precheck: template/Makefile.in defs/gmake.mk common.mk
test_prechecks := $(filter $(ORDERED_TEST_TARGETS),\
	test-leaked-globals \
	test-all \
	test-spec \
	test-syntax-suggest \
	test-bundler \
	test-bundler-parallel \
	test-bundled-gems\
	)
prev_test := $(subst test-bundler-parallel,test-bundler,$(test_prechecks))
prev_test := $(addsuffix -precheck,$(prev_test))
first_test_prechecks := $(prev_test)

$(foreach test,$(ORDERED_TEST_TARGETS), \
	$(eval yes-$(value test): $(addprefix yes-,$(value prev_test))); \
	$(eval no-$(value test): $(addprefix no-,$(value prev_test))); \
	$(eval prev_test := $(value test)))
endif

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
	$(Q) $(PURIFY) $(CC) $(EXE_LDFLAGS) $(XLDFLAGS) rubystub.$(OBJEXT) $(EXTOBJS) $(LIBRUBYARG) $(MAINLIBS) $(LIBS) $(EXTLIBS) $(OUTFLAG)$@
	$(Q) $(POSTLINK)
	$(if $(STRIP),$(Q) $(STRIP) $@)

$(SCRIPTBINDIR)%$(EXEEXT): bin/% $(STUBPROGRAM) \
			   $(if $(SCRIPTBINDIR),$(TIMESTAMPDIR)/.exec.time)
	$(ECHO) generating $@
	$(Q) { cat $(STUBPROGRAM); echo; sed -e '1{' -e '/^#!.*ruby/!i\' -e '#!/bin/ruby' -e '}' $<; } > $@
	$(Q) chmod +x $@
	$(Q) $(POSTLINK)

$(SCRIPTBINDIR):
	$(Q) mkdir $@

.PHONY: commit
COMMIT_PREPARE := $(subst :,\:,$(filter-out commit do-commit,$(MAKECMDGOALS))) up

commit: pre-commit $(DOT_WAIT) do-commit $(DOT_WAIT) post_commit
pre-commit: $(COMMIT_PREPARE)
do-commit: $(if $(DOT_WAIT),,pre-commit)
	@$(BASERUBY) -C "$(srcdir)" -I./tool/lib -rvcs -e 'VCS.detect(".").commit'
post-commit: $(if $(DOT_WAIT),,do-commit)
	+$(Q) \
	{ \
	  $(in-srcdir) \
	  exec sed -f tool/prereq.status defs/gmake.mk template/Makefile.in common.mk depend; \
	} | \
	$(MAKE) $(mflags) Q=$(Q) ECHO=$(ECHO) \
		top_srcdir="$(top_srcdir)" srcdir="$(srcdir)" srcs_vpath="" CHDIR="$(CHDIR)" \
		BOOTSTRAPRUBY="$(BOOTSTRAPRUBY)" BOOTSTRAPRUBY_OPT="$(BOOTSTRAPRUBY_OPT)" \
		MINIRUBY="$(BASERUBY)" BASERUBY="$(BASERUBY)" HAVE_BASERUBY="$(HAVE_BASERUBY)" \
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
	"  checkout-github:       checkout GitHub Pull Request [PR=1234]" \
	"  pull-github:           rebase GitHub Pull Request to new worktree [PR=1234]" \
	"  update-github:         merge master branch and push it to Pull Request [PR=1234]" \
	"  tags:                  generate TAGS file" \
	""

# 1. squeeze spaces
# 2. strip and skip comment/empty lines
# 3. "gem x.y.z URL xxxxxx" -> "gem|x.y.z|xxxxxx|URL"
# 4. "gem x.y.z URL" -> "gem-x.y.z"
bundled-gems := $(shell sed \
	-e 's/[ 	][ 	]*/ /g' \
	-e 's/^ //;s/\#.*//;s/ *$$//;/^$$/d' \
	$(if $(filter yes,$(HAVE_GIT)), \
	-e 's/^\(.*\) \(.*\) \(.*\) \(.*\)/\1|\2|\4|\3/' \
	) \
	-e 's/ /-/;s/ .*//' \
	 $(srcdir)/gems/bundled_gems)

bundled-gems-rev := $(filter-out $(subst |,,$(bundled-gems)),$(bundled-gems))
bundled-gems := $(filter-out $(bundled-gems-rev),$(bundled-gems))

# calls $(1) with name, version, revision, URL
foreach-bundled-gems-rev = \
    $(foreach g,$(bundled-gems-rev),$(call foreach-bundled-gems-rev-0,$(1),$(subst |, ,$(value g))))
foreach-bundled-gems-rev-0 = \
    $(call $(1),$(word 1,$(2)),$(word 2,$(2)),$(word 3,$(2)),$(word 4,$(2)))
bundled-gem-gemfile = $(srcdir)/gems/$(1)-$(2).gem
bundled-gem-gemspec = $(srcdir)/gems/src/$(1)/$(1).gemspec
bundled-gem-extracted = $(srcdir)/.bundle/gems/$(1)-$(2)
bundled-gem-revision = $(srcdir)/.bundle/.timestamp/$(1).revision

update-gems: | $(patsubst %,$(srcdir)/gems/%.gem,$(bundled-gems))
update-gems: | $(call foreach-bundled-gems-rev,bundled-gem-gemfile)
update-gems: | $(call foreach-bundled-gems-rev,bundled-gem-gemspec)

test-bundler-precheck: | $(srcdir)/.bundle/cache

$(srcdir)/.bundle/cache:
	$(MAKEDIRS) $(@D) $(CACHE_DIR)
	$(LN_S) ../.downloaded-cache $@

$(srcdir)/gems/%.gem:
	$(ECHO) Downloading bundled gem $*...
	$(Q) $(BASERUBY) -C "$(srcdir)" \
	    -I./tool -rdownloader \
	    -e 'gem = "$(@F)"' \
	    -e 'old = Dir.glob("gems/"+gem.sub(/-[^-]*$$/, "-*.gem"))' \
	    -e 'Downloader::RubyGems.download(gem, "gems", nil) and' \
	    -e '(old.delete("gems/#{gem}"); !old.empty?) and' \
	    -e 'File.unlink(*old) and' \
	    -e 'FileUtils.rm_rf(old.map{'"|n|"'n.chomp(".gem")})'

extract-gems: | $(patsubst %,$(srcdir)/.bundle/gems/%,$(bundled-gems))
extract-gems: | $(call foreach-bundled-gems-rev,bundled-gem-extracted)

$(srcdir)/.bundle/gems/%: $(srcdir)/gems/%.gem | .bundle/gems
	$(ECHO) Extracting bundle gem $*...
	$(Q) $(BASERUBY) -C "$(srcdir)" \
	    -Itool/lib -rbundled_gem \
	    -e 'BundledGem.unpack("gems/$(@F).gem", ".bundle")'

$(srcdir)/.bundle/.timestamp:
	$(MAKEDIRS) $@

define build-gem
$(srcdir)/gems/src/$(1)/.git: | $(srcdir)/gems/src
	$(ECHO) Cloning $(4)
	$(Q) $(GIT) clone --depth=1 --no-tags $(4) $$(@D)

$(bundled-gem-revision): \
	$(if $(if $(wildcard $$(@)),$(filter $(3),$(shell cat $$(@)))),,PHONY) \
	| $(srcdir)/.bundle/.timestamp $(srcdir)/gems/src/$(1)/.git
	$(ECHO) Update $(1) to $(3)
	$(Q) $(CHDIR) "$(srcdir)/gems/src/$(1)" && \
	    if [ `$(GIT) rev-parse HEAD` != $(3) ]; then \
	        $(GIT) fetch origin $(3) && \
	        $(GIT) checkout --detach $(3) && \
	        :; \
	    fi
	echo $(3) | $(IFCHANGE) $$(@) -

# The repository of minitest does not include minitest.gemspec because it uses hoe.
# This creates a dummy gemspec.
$(bundled-gem-gemspec): $(bundled-gem-revision) \
	| $(srcdir)/gems/src/$(1)/.git
	$(Q) $(BASERUBY) -I$(tooldir)/lib -rbundled_gem -e 'BundledGem.dummy_gemspec(*ARGV)' $$(@)

$(bundled-gem-gemfile): $(bundled-gem-gemspec) $(bundled-gem-revision)
	$(ECHO) Building $(1)@$(3) to $$(@)
	$(Q) $(BASERUBY) -C "$(srcdir)" \
	    -Itool/lib -rbundled_gem \
	    -e 'BundledGem.build("gems/src/$(1)/$(1).gemspec", "$(2)", "gems", validation: false)'

endef
define build-gem-0
$(eval $(call build-gem,$(1),$(2),$(3),$(4)))
endef

$(call foreach-bundled-gems-rev,build-gem-0)

$(srcdir)/gems/src:
	$(MAKEDIRS) $@

$(srcdir)/.bundle/gems:
	$(MAKEDIRS) $@

ifneq ($(DOT_WAIT),)
up:: $(DOT_WAIT) after-update
endif

ifneq ($(filter update-bundled_gems refresh-gems,$(MAKECMDGOALS)),)
update-gems: update-bundled_gems
endif

.SECONDARY: update-unicode-files
.SECONDARY: update-unicode-auxiliary-files
.SECONDARY: update-unicode-ucd-emoji-files
.SECONDARY: update-unicode-emoji-files

ifneq ($(DOT_WAIT),)
.NOTPARALLEL: update-unicode
.NOTPARALLEL: update-unicode-files
.NOTPARALLEL: update-unicode-auxiliary-files
.NOTPARALLEL: update-unicode-ucd-emoji-files
.NOTPARALLEL: update-unicode-emoji-files
.NOTPARALLEL: $(UNICODE_FILES) $(UNICODE_PROPERTY_FILES)
.NOTPARALLEL: $(UNICODE_AUXILIARY_FILES)
.NOTPARALLEL: $(UNICODE_UCD_EMOJI_FILES) $(UNICODE_EMOJI_FILES)
endif

ifeq ($(HAVE_GIT),yes)
REVISION_LATEST := $(shell $(CHDIR) $(srcdir) && $(GIT) log -1 --format=%H 2>/dev/null)
else
REVISION_LATEST := update
endif
REVISION_IN_HEADER := $(shell sed '/^\#define RUBY_FULL_REVISION "\(.*\)"/!d;s//\1/;q' $(wildcard $(srcdir)/revision.h revision.h) /dev/null 2>/dev/null)
ifeq ($(REVISION_IN_HEADER),)
REVISION_IN_HEADER := none
endif
ifneq ($(REVISION_IN_HEADER),$(REVISION_LATEST))
$(REVISION_H): PHONY
endif

include $(top_srcdir)/yjit/yjit.mk
include $(top_srcdir)/zjit/zjit.mk
include $(top_srcdir)/defs/jit.mk

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

clean-local:: TARGET_SO = $(PROGRAM) $(WPROGRAM) $(LIBRUBY_SO) $(STATIC_RUBY) miniruby goruby
clean-local::
	-$(Q)$(RMALL) $(cleanlibs)

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
$(RUBYSPEC_CAPIEXT)/%.$(DLEXT): $(srcdir)/$(RUBYSPEC_CAPIEXT)/%.c $(RUBYSPEC_CAPIEXT_DEPS) \
	| build-ext
	$(ECHO) building $@
	$(Q) $(MAKEDIRS) $(@D)
	$(Q) $(DLDSHARED) -L. $(XDLDFLAGS) $(XLDFLAGS) $(LDFLAGS) $(INCFLAGS) $(CPPFLAGS) $(OUTFLAG)$@ $< $(LIBRUBYARG)
ifneq ($(POSTLINK),)
	$(Q) $(POSTLINK)
endif
	$(Q) $(RMALL) $@.*

RUBYSPEC_CAPIEXT_SO := $(patsubst %.c,$(RUBYSPEC_CAPIEXT)/%.$(DLEXT),$(notdir $(wildcard $(srcdir)/$(RUBYSPEC_CAPIEXT)/*.c)))
rubyspec-capiext: $(RUBYSPEC_CAPIEXT_SO)
	@ $(NULLCMD)

ifeq ($(ENABLE_SHARED),yes)
exts: rubyspec-capiext
endif

spec/%/ spec/%_spec.rb: programs exts PHONY
	+$(RUNRUBY) -r./$(arch)-fake $(srcdir)/spec/mspec/bin/mspec-run -B $(srcdir)/spec/default.mspec $(SPECOPTS) $(patsubst %,$(srcdir)/%,$@)

ruby.pc: $(filter-out ruby.pc,$(ruby_pc))

matz: up
	$(eval OLD := $(MAJOR).$(MINOR).0)
	$(eval MINOR := $(shell expr $(MINOR) + 1))
	$(eval NEW := $(MAJOR).$(MINOR).0)
	$(eval message := Development of $(NEW) started.)
	$(eval files := include/ruby/version.h include/ruby/internal/abi.h)
	$(GIT) -C $(srcdir) mv -f NEWS.md doc/NEWS/NEWS-$(OLD).md
	$(GIT) -C $(srcdir) commit -m "[DOC] Flush NEWS.md"
	sed -i~ \
	-e "s/^\(#define RUBY_API_VERSION_MINOR\) .*/\1 $(MINOR)/" \
	-e "s/^\(#define RUBY_ABI_VERSION\) .*/\1 0/" \
	 $(files:%=$(srcdir)/%)
	$(GIT) -C $(srcdir) add $(files)
	$(BASERUBY) -C $(srcdir) -p -00 \
	-e 'BEGIN {old, new = ARGV.shift(2); STDOUT.reopen("NEWS.md")}' \
	-e 'case $$.' \
	-e 'when 1; $$_.sub!(/Ruby \K[0-9.]+/, new)' \
	-e 'when 2; $$_.sub!(/\*\*\K[0-9.]+(?=\*\*)/, old)' \
	-e 'end' \
	-e 'next if /^[\[ *]/ =~ $$_' \
	-e '$$_.sub!(/\n{2,}\z/, "\n\n")' \
	$(OLD) $(NEW) doc/NEWS/NEWS-$(OLD).md
	$(GIT) -C $(srcdir) add NEWS.md
	$(GIT) -C $(srcdir) commit -m "$(message)"

tags:
	$(MAKE) GIT="$(GIT)" -C "$(srcdir)" -f defs/tags.mk


# ripper_srcs makes all sources at once. invoking this target multiple
# times in parallel means all sources will be built for the number of
# sources times respectively.
ifneq ($(DOT_WAIT),)
.NOTPARALLEL: ripper_srcs
else
ripper_src =
$(foreach r,$(RIPPER_SRCS),$(eval $(value r): | $(value ripper_src))\
	$(eval ripper_src := $(value r)))
ripper_srcs: $(ripper_src)
endif
