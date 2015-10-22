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
yes-test-knownbug: $(TEST_DEPENDS) yes-btest-ruby
yes-btest-ruby: $(TEST_DEPENDS) yes-test-sample
yes-test-sample: $(TEST_DEPENDS)
endif
ifneq ($(filter $(CHECK_TARGETS),$(MAKECMDGOALS)) $(filter test-all,$(TEST_TARGETS)),)
yes-test-testframework yes-test-almost yes-test-ruby: $(filter-out %test-all %test-ruby check%,$(TEST_TARGETS))
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
sudo-precheck: test
install-prereq: sudo-precheck
yes-test-all no-test-all: install
endif
