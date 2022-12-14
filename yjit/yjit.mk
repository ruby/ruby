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

# YJIT_SUPPORT=yes when `configure` gets `--enable-yjit`
ifeq ($(YJIT_SUPPORT),yes)
$(YJIT_LIBS): $(YJIT_SRC_FILES)
	$(ECHO) 'building Rust YJIT (release mode)'
	$(Q) $(RUSTC) $(YJIT_RUSTC_ARGS)
	$(YJIT_LIB_TOUCH)
else ifeq ($(YJIT_SUPPORT),no)
$(YJIT_LIBS):
	$(ECHO) 'Error: Tried to build YJIT without configuring it first. Check `make showconfig`?'
	@false
else ifeq ($(YJIT_SUPPORT),$(filter dev dev_nodebug stats,$(YJIT_SUPPORT)))
$(YJIT_LIBS): $(YJIT_SRC_FILES)
	$(ECHO) 'building Rust YJIT ($(YJIT_SUPPORT) mode)'
	$(Q)$(CHDIR) $(top_srcdir)/yjit && \
	        CARGO_TARGET_DIR='$(CARGO_TARGET_DIR)' \
	        CARGO_TERM_PROGRESS_WHEN='never' \
	        $(CARGO) $(CARGO_VERBOSE) build $(CARGO_BUILD_ARGS)
	$(YJIT_LIB_TOUCH)
else
endif

# Put this here instead of in common.mk to avoid breaking nmake builds
miniruby$(EXEEXT): $(YJIT_LIBS)

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

# Generate Rust bindings. See source for details.
# Needs `./configure --enable-yjit=dev` and Clang.
ifneq ($(strip $(CARGO)),) # if configure found Cargo
.PHONY: yjit-bindgen yjit-bindgen-show-unused
yjit-bindgen: yjit.$(OBJEXT)
	YJIT_SRC_ROOT_PATH='$(top_srcdir)' $(CARGO) run --manifest-path '$(top_srcdir)/yjit/bindgen/Cargo.toml' -- $(CFLAGS) $(XCFLAGS) $(CPPFLAGS)
	$(Q) if [ 'x$(HAVE_GIT)' = xyes ]; then $(GIT) -C "$(top_srcdir)" diff --exit-code yjit/src/cruby_bindings.inc.rs; fi

check-yjit-bindgen-unused: yjit.$(OBJEXT)
	RUST_LOG=warn YJIT_SRC_ROOT_PATH='$(top_srcdir)' $(CARGO) run --manifest-path '$(top_srcdir)/yjit/bindgen/Cargo.toml' -- $(CFLAGS) $(XCFLAGS) $(CPPFLAGS) 2>&1 | (! grep "unused option: --allow")
endif
