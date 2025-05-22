# -*- mode: makefile-gmake; indent-tabs-mode: t -*-

# Show Cargo progress when doing `make V=1`
CARGO_VERBOSE_0 = -q
CARGO_VERBOSE_1 =
CARGO_VERBOSE = $(CARGO_VERBOSE_$(V))

YJIT_SRC_FILES = $(wildcard \
	$(top_srcdir)/yjit/Cargo.* \
	$(top_srcdir)/yjit/src/*.rs \
	$(top_srcdir)/yjit/src/*/*.rs \
	$(top_srcdir)/yjit/src/*/*/*.rs \
	$(top_srcdir)/yjit/src/*/*/*/*.rs \
	)

# Because of Cargo cache, if the actual binary is not changed from the
# previous build, the mtime is preserved as the cached file.
# This means the target is not updated actually, and it will need to
# rebuild at the next build.
YJIT_LIB_TOUCH = touch $@

# Absolute path to match RUST_LIB rules to avoid picking
# the "target" dir in the source directory through VPATH.
BUILD_YJIT_LIBS = $(TOP_BUILD_DIR)/$(YJIT_LIBS)

# YJIT_SUPPORT=yes when `configure` gets `--enable-yjit`
ifeq ($(YJIT_SUPPORT),yes)
yjit-libs: $(BUILD_YJIT_LIBS)
$(BUILD_YJIT_LIBS): $(YJIT_SRC_FILES)
	$(ECHO) 'building Rust YJIT (release mode)'
	+$(Q) $(RUSTC) $(YJIT_RUSTC_ARGS)
	$(YJIT_LIB_TOUCH)
endif

ifneq ($(YJIT_SUPPORT),no)
$(RUST_LIB): $(YJIT_SRC_FILES)
endif

# By using YJIT_BENCH_OPTS instead of RUN_OPTS, you can skip passing the options to `make install`
YJIT_BENCH_OPTS = $(RUN_OPTS) --enable-gems
YJIT_BENCH = benchmarks/railsbench/benchmark.rb

# Run yjit-bench's ./run_once.sh for CI
yjit-bench: install update-yjit-bench PHONY
	$(Q) cd $(srcdir)/yjit-bench && PATH=$(prefix)/bin:$$PATH \
		./run_once.sh $(YJIT_BENCH_OPTS) $(YJIT_BENCH)

update-yjit-bench:
	$(Q) $(tooldir)/git-refresh -C $(srcdir) --branch main \
		https://github.com/Shopify/yjit-bench yjit-bench $(GIT_OPTS)

RUST_VERSION = +1.58.0

# Gives quick feedback about YJIT. Not a replacement for a full test run.
.PHONY: yjit-smoke-test
yjit-smoke-test:
ifneq ($(strip $(CARGO)),)
	$(CARGO) test --all-features -q --manifest-path='$(top_srcdir)/yjit/Cargo.toml'
endif
	$(MAKE) btest RUN_OPTS='--yjit-call-threshold=1' BTESTS=-j
	$(MAKE) test-all TESTS='$(top_srcdir)/test/ruby/test_yjit.rb'

YJIT_BINDGEN_DIFF_OPTS =

# Generate Rust bindings. See source for details.
# Needs `./configure --enable-yjit=dev` and Clang.
ifneq ($(strip $(CARGO)),) # if configure found Cargo
.PHONY: yjit-bindgen yjit-bindgen-show-unused
yjit-bindgen: yjit.$(OBJEXT)
	YJIT_SRC_ROOT_PATH='$(top_srcdir)' $(CARGO) run --manifest-path '$(top_srcdir)/yjit/bindgen/Cargo.toml' -- $(CFLAGS) $(XCFLAGS) $(CPPFLAGS)
	$(Q) if [ 'x$(HAVE_GIT)' = xyes ]; then $(GIT) -C "$(top_srcdir)" diff $(YJIT_BINDGEN_DIFF_OPTS) yjit/src/cruby_bindings.inc.rs; fi

check-yjit-bindgen-unused: yjit.$(OBJEXT)
	RUST_LOG=warn YJIT_SRC_ROOT_PATH='$(top_srcdir)' $(CARGO) run --manifest-path '$(top_srcdir)/yjit/bindgen/Cargo.toml' -- $(CFLAGS) $(XCFLAGS) $(CPPFLAGS) 2>&1 | (! grep "unused option: --allow")
endif
