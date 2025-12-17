# -*- mode: makefile-gmake; indent-tabs-mode: t -*-

# Put no definitions when ZJIT isn't configured
ifneq ($(ZJIT_SUPPORT),no)

ZJIT_SRC_FILES = $(wildcard \
	$(top_srcdir)/zjit/Cargo.* \
	$(top_srcdir)/zjit/src/*.rs \
	$(top_srcdir)/zjit/src/*/*.rs \
	$(top_srcdir)/zjit/src/*/*/*.rs \
	$(top_srcdir)/zjit/src/*/*/*/*.rs \
	$(top_srcdir)/jit/src/lib.rs \
	)

$(RUST_LIB): $(ZJIT_SRC_FILES)

# Absolute path to match RUST_LIB rules to avoid picking
# the "target" dir in the source directory through VPATH.
BUILD_ZJIT_LIBS = $(TOP_BUILD_DIR)/$(ZJIT_LIBS)

# In a ZJIT-only build (no YJIT)
ifneq ($(strip $(ZJIT_LIBS)),)
$(BUILD_ZJIT_LIBS): $(ZJIT_SRC_FILES)
	$(ECHO) 'building Rust ZJIT (release mode)'
	$(gnumake_recursive)$(Q) $(RUSTC) $(ZJIT_RUSTC_ARGS)
else ifneq ($(strip $(RLIB_DIR)),) # combo build
# Absolute path to avoid VPATH ambiguity
ZJIT_RLIB = $(TOP_BUILD_DIR)/$(RLIB_DIR)/libzjit.rlib

$(ZJIT_RLIB): $(ZJIT_SRC_FILES)
	$(ECHO) 'building $(@F)'
	$(gnumake_recursive)$(Q) $(RUSTC) '-L$(@D)' --extern=jit $(ZJIT_RUSTC_ARGS)

$(RUST_LIB): $(ZJIT_RLIB)
endif # ifneq ($(strip $(ZJIT_LIBS)),)

# By using ZJIT_BENCH_OPTS instead of RUN_OPTS, you can skip passing the options to `make install`
ZJIT_BENCH_OPTS = $(RUN_OPTS) --enable-gems
ZJIT_BENCH = benchmarks/railsbench/benchmark.rb

# Run zjit-bench's ./run_once.sh for CI
zjit-bench: install update-zjit-bench PHONY
	$(Q) cd $(srcdir)/zjit-bench && PATH=$(prefix)/bin:$$PATH \
		./run_once.sh $(ZJIT_BENCH_OPTS) $(ZJIT_BENCH)

update-zjit-bench:
	$(Q) $(tooldir)/git-refresh -C $(srcdir) --branch main \
		https://github.com/Shopify/zjit-bench zjit-bench $(GIT_OPTS)

# Gives quick feedback about ZJIT. Not a replacement for a full test run.
.PHONY: zjit-check
zjit-check:
	$(MAKE) zjit-test
	$(MAKE) test-all TESTS='$(top_srcdir)/test/ruby/test_zjit.rb'

ZJIT_BINDGEN_DIFF_OPTS =

# Generate Rust bindings. See source for details.
# Needs `./configure --enable-zjit=dev` and Clang.
ifneq ($(strip $(CARGO)),) # if configure found Cargo
.PHONY: zjit-bindgen zjit-bindgen-show-unused zjit-test zjit-test-update
.PHONY: zjit-test-debug zjit-test-lldb zjit-test-gdb zjit-test-rr
zjit-bindgen: zjit.$(OBJEXT)
	ZJIT_SRC_ROOT_PATH='$(top_srcdir)' BINDGEN_JIT_NAME=zjit $(CARGO) run --manifest-path '$(top_srcdir)/zjit/bindgen/Cargo.toml' -- $(CFLAGS) $(XCFLAGS) $(CPPFLAGS)
	$(Q) if [ 'x$(HAVE_GIT)' = xyes ]; then $(GIT) -C "$(top_srcdir)" diff $(ZJIT_BINDGEN_DIFF_OPTS) zjit/src/cruby_bindings.inc.rs; fi

# Build env should roughly match what's used for miniruby to help with caching.
ZJIT_NEXTEST_ENV := RUBY_BUILD_DIR='$(TOP_BUILD_DIR)' \
    RUBY_LD_FLAGS='$(LDFLAGS) $(XLDFLAGS) $(MAINLIBS)' \
    MACOSX_DEPLOYMENT_TARGET=11.0 \
    CARGO_TARGET_DIR='$(CARGO_TARGET_DIR)'

# We need `cargo nextest` for its one-process-per execution execution model
# since we can only boot the VM once per process. Normal `cargo test`
# runs tests in threads and can't handle this.
#
# On darwin, it's available through `brew install cargo-nextest`. See
# https://nexte.st/docs/installation/pre-built-binaries/ otherwise.
zjit-test: libminiruby.a
	@set +e; \
	$(ZJIT_NEXTEST_ENV) $(CARGO) nextest run \
		--manifest-path '$(top_srcdir)/zjit/Cargo.toml' \
		--no-fail-fast \
		'--features=$(ZJIT_TEST_FEATURES)' \
		$(ZJIT_TESTS); \
	exit_code=$$?; \
	if [ -f '$(top_srcdir)/zjit/src/.hir.rs.pending-snap' ]; then \
		echo ""; \
		echo "Pending snapshots found. Accept with: make zjit-test-update"; \
	fi; \
	exit $$exit_code

# Accept all pending snapshots (requires cargo-insta)
# Install with: cargo install cargo-insta
zjit-test-update:
	@$(CARGO) insta --version >/dev/null 2>&1 || { echo "Error: cargo-insta is not installed. Install with: cargo install cargo-insta"; exit 1; }
	@$(CARGO) insta accept --manifest-path '$(top_srcdir)/zjit/Cargo.toml'

ZJIT_DEBUGGER =
ZJIT_DEBUGGER_OPTS =

# Run a ZJIT test written with Rust #[test] under $(ZJIT_DEBUGGER)
zjit-test-debug: libminiruby.a
	$(Q)set -eu; \
	    if [ -z '$(ZJIT_TESTS)' ]; then \
		echo "Please pass a ZJIT_TESTS=... filter to make."; \
		echo "Many tests only work when it's the only test in the process."; \
		exit 1; \
	    fi; \
	    exe_path=`$(ZJIT_NEXTEST_ENV) \
	    $(CARGO) nextest list --manifest-path '$(top_srcdir)/zjit/Cargo.toml' --message-format json --list-type=binaries-only | \
	    $(BASERUBY) -rjson -e 'puts JSON.load(STDIN.read).dig("rust-binaries", "zjit", "binary-path")'`; \
	    exec $(ZJIT_DEBUGGER) $$exe_path $(ZJIT_DEBUGGER_OPTS) --test-threads=1 $(ZJIT_TESTS)

# Run a ZJIT test written with Rust #[test] under LLDB
zjit-test-lldb:
	$(Q) $(MAKE) zjit-test-debug ZJIT_DEBUGGER=lldb ZJIT_DEBUGGER_OPTS=--

# Run a ZJIT test written with Rust #[test] under GDB
zjit-test-gdb: libminiruby.a
	$(Q) $(MAKE) zjit-test-debug ZJIT_DEBUGGER="gdb --args"

# Run a ZJIT test written with Rust #[test] under rr-debugger
zjit-test-rr: libminiruby.a
	$(Q) $(MAKE) zjit-test-debug ZJIT_DEBUGGER="rr record"

# A library for booting miniruby in tests.
# Why not use libruby-static.a for this?
#  - Initialization of the full ruby involves dynamic linking for e.g. transcoding implementations
#    our tests don't need these functionalities so good to avoid their complexity.
#  - By being mini, it's faster to build
#  - Less likely to break since later stages of the build process also rely on miniruby.
libminiruby.a: miniruby$(EXEEXT)
	$(ECHO) linking static-library $@
	$(Q) $(AR) $(ARFLAGS) $@ $(MINIOBJS) $(COMMONOBJS)

libminiruby: libminiruby.a

endif # ifneq ($(strip $(CARGO)),
endif # ifneq ($(ZJIT_SUPPORT),no)
