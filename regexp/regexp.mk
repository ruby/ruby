# -*- mode: makefile-gmake; indent-tabs-mode: t -*-

# Put no definitions when the Rust regexp engine isn't configured
ifneq ($(RUST_REGEXP_SUPPORT),no)

REGEXP_SRC_FILES = $(wildcard \
	$(top_srcdir)/regexp/Cargo.* \
	$(top_srcdir)/regexp/src/*.rs \
	$(top_srcdir)/regexp/src/*/*.rs \
	$(top_srcdir)/regexp/src/*/*/*.rs \
	)

$(RUST_LIB): $(REGEXP_SRC_FILES)

# Absolute path to match RUST_LIB rules to avoid picking
# the "target" dir in the source directory through VPATH.
BUILD_REGEXP_LIBS = $(TOP_BUILD_DIR)/$(REGEXP_LIBS)

# In a build where the regexp engine is the only Rust crate
ifneq ($(strip $(REGEXP_LIBS)),)
$(BUILD_REGEXP_LIBS): $(REGEXP_SRC_FILES) target/.rustc-version
	$(ECHO) 'building Rust regexp engine (release mode)'
	$(gnumake_recursive)$(Q) $(RUSTC) $(REGEXP_RUSTC_ARGS)
else ifneq ($(strip $(RLIB_DIR)),) # combo build
# Absolute path to avoid VPATH ambiguity
REGEXP_RLIB = $(TOP_BUILD_DIR)/$(RLIB_DIR)/libregexp.rlib

$(REGEXP_RLIB): $(REGEXP_SRC_FILES) target/.rustc-version
	$(ECHO) 'building $(@F)'
	$(gnumake_recursive)$(Q) $(RUSTC) '-L$(@D)' $(REGEXP_RUSTC_ARGS)

$(RUST_LIB): $(REGEXP_RLIB)
RUST_CRATE_EXTERNS += --extern=regexp --cfg 'feature="regexp"'
endif # ifneq ($(strip $(REGEXP_LIBS)),)

# Gives quick feedback about the regexp engine. Not a replacement for a full test run.
.PHONY: regexp-check
regexp-check:
ifneq ($(strip $(CARGO)),)
	$(CARGO) test -q --manifest-path='$(top_srcdir)/regexp/Cargo.toml'
endif
	$(MAKE) test-all TESTS='$(top_srcdir)/test/ruby/test_regexp.rb' RUN_OPTS='--regexp-engine=rust'

endif # ifneq ($(RUST_REGEXP_SUPPORT),no)
