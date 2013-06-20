# -*- makefile-gmake -*-
TEST_TARGETS := $(filter check test check% test% btest%,$(MAKECMDGOALS))
TEST_TARGETS += $(subst check,test-all,$(patsubst check-%,test-%,$(TEST_TARGETS)))
TEST_TARGETS := $(patsubst test-%,yes-test-%,$(patsubst btest-%,yes-btest-%,$(TEST_TARGETS)))
TEST_DEPENDS := $(if $(TEST_TARGETS),$(filter all main exts,$(MAKECMDGOALS)))
TEST_DEPENDS += $(TEST_DEPENDS) $(if $(filter check%,$(MAKECMDGOALS)),main)

ifneq ($(filter check% test,$(MAKECMDGOALS)),)
yes-test-knownbug: $(TEST_DEPENDS) yes-btest-ruby
yes-btest-ruby: $(TEST_DEPENDS) yes-test-sample
yes-test-sample: $(TEST_DEPENDS)
endif
ifneq ($(filter check%,$(MAKECMDGOALS)) $(filter test-all,$(TEST_TARGETS)),)
yes-test-all yes-test-ruby: $(filter-out %test-all %test-ruby check%,$(TEST_TARGETS))
endif
ifneq ($(filter check%,$(MAKECMDGOALS))$(if $(filter test-all,$(MAKECMDGOALS)),$(filter test-knownbug,$(MAKECMDGOALS))),)
yes-test-all yes-test-ruby: yes-test-knownbug
endif

$(TEST_TARGETS): $(TEST_DEPENDS)

ifneq ($(if $(filter install,$(MAKECMDGOALS)),$(filter uninstall,$(MAKECMDGOALS))),)
install-targets := $(filter install uninstall,$(MAKECMDGOALS))
$(word 1,$(install-targets)): $(word 0,$(install-targets))
endif

ifneq ($(filter reinstall,$(MAKECMDGOALS)),)
install: uninstall
endif
