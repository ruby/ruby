# -*- mode: makefile-gmake; indent-tabs-mode: t -*-

# Show Cargo progress when doing `make V=1`
CARGO_VERBOSE_0 = -q
CARGO_VERBOSE_1 =
CARGO_VERBOSE = $(CARGO_VERBOSE_$(V))

ZJIT_SRC_FILES = $(wildcard \
	$(top_srcdir)/zjit/Cargo.* \
	$(top_srcdir)/zjit/src/*.rs \
	$(top_srcdir)/zjit/src/*/*.rs \
	$(top_srcdir)/zjit/src/*/*/*.rs \
	$(top_srcdir)/zjit/src/*/*/*/*.rs \
	)

# Because of Cargo cache, if the actual binary is not changed from the
# previous build, the mtime is preserved as the cached file.
# This means the target is not updated actually, and it will need to
# rebuild at the next build.
ZJIT_LIB_TOUCH = touch $@

# ZJIT_SUPPORT=yes when `configure` gets `--enable-zjit`
ifeq ($(ZJIT_SUPPORT),yes)
$(ZJIT_LIBS): $(ZJIT_SRC_FILES)
	$(ECHO) 'building Rust ZJIT (release mode)'
	+$(Q) $(RUSTC) $(ZJIT_RUSTC_ARGS)
	$(ZJIT_LIB_TOUCH)
else ifeq ($(ZJIT_SUPPORT),no)
$(ZJIT_LIBS):
	$(ECHO) 'Error: Tried to build ZJIT without configuring it first. Check `make showconfig`?'
	@false
else ifeq ($(ZJIT_SUPPORT),$(filter dev dev_nodebug stats,$(ZJIT_SUPPORT)))
# NOTE: MACOSX_DEPLOYMENT_TARGET to match `rustc --print deployment-target` to avoid the warning below.
#    ld: warning: object file (zjit/target/debug/libzjit.a(<libcapstone object>)) was built for
#    newer macOS version (15.2) than being linked (15.0)
# We don't use newer macOS feature as of yet.
$(ZJIT_LIBS): $(ZJIT_SRC_FILES)
	$(ECHO) 'building Rust ZJIT ($(ZJIT_SUPPORT) mode)'
	+$(Q)$(CHDIR) $(top_srcdir)/zjit && \
	        CARGO_TARGET_DIR='$(ZJIT_CARGO_TARGET_DIR)' \
	        CARGO_TERM_PROGRESS_WHEN='never' \
	        MACOSX_DEPLOYMENT_TARGET=11.0 \
	        $(CARGO) $(CARGO_VERBOSE) build $(ZJIT_CARGO_BUILD_ARGS)
	$(ZJIT_LIB_TOUCH)
else
endif

zjit-libobj: $(ZJIT_LIBOBJ)

ZJIT_LIB_SYMBOLS = $(ZJIT_LIBS:.a=).symbols
$(ZJIT_LIBOBJ): $(ZJIT_LIBS)
	$(ECHO) 'partial linking $(ZJIT_LIBS) into $@'
ifneq ($(findstring darwin,$(target_os)),)
	$(Q) $(CC) -nodefaultlibs -r -o $@ -exported_symbols_list $(ZJIT_LIB_SYMBOLS) $(ZJIT_LIBS)
else
	$(Q) $(LD) -r -o $@ --whole-archive $(ZJIT_LIBS)
	-$(Q) $(OBJCOPY) --wildcard --keep-global-symbol='$(SYMBOL_PREFIX)rb_*' $(@)
endif

# For Darwin only: a list of symbols that we want the glommed Rust static lib to export.
# Unfortunately, using wildcard like '_rb_*' with -exported-symbol does not work, at least
# not on version 820.1. Assume llvm-nm, so XCode 8.0 (from 2016) or newer.
#
# The -exported_symbols_list pulls out the right archive members. Symbols not listed
# in the list are made private extern, which are in turn made local as we're using `ld -r`.
# Note, section about -keep_private_externs in ld's man page hints at this behavior on which
# we rely.
ifneq ($(findstring darwin,$(target_os)),)
$(ZJIT_LIB_SYMBOLS): $(ZJIT_LIBS)
	$(Q) $(tooldir)/darwin-ar $(NM) --defined-only --extern-only $(ZJIT_LIBS) | \
	sed -n -e 's/.* //' -e '/^$(SYMBOL_PREFIX)rb_/p' \
	-e '/^$(SYMBOL_PREFIX)rust_eh_personality/p' \
	> $@

$(ZJIT_LIBOBJ): $(ZJIT_LIB_SYMBOLS)
endif

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
.PHONY: zjit-test-all
zjit-test-all:
	$(MAKE) zjit-test
	$(MAKE) test-all TESTS='$(top_srcdir)/test/ruby/test_zjit.rb'

ZJIT_BINDGEN_DIFF_OPTS =

# Generate Rust bindings. See source for details.
# Needs `./configure --enable-zjit=dev` and Clang.
ifneq ($(strip $(CARGO)),) # if configure found Cargo
.PHONY: zjit-bindgen zjit-bindgen-show-unused zjit-test zjit-test-lldb
zjit-bindgen: zjit.$(OBJEXT)
	ZJIT_SRC_ROOT_PATH='$(top_srcdir)' BINDGEN_JIT_NAME=zjit $(CARGO) run --manifest-path '$(top_srcdir)/zjit/bindgen/Cargo.toml' -- $(CFLAGS) $(XCFLAGS) $(CPPFLAGS)
	$(Q) if [ 'x$(HAVE_GIT)' = xyes ]; then $(GIT) -C "$(top_srcdir)" diff $(ZJIT_BINDGEN_DIFF_OPTS) zjit/src/cruby_bindings.inc.rs; fi

# We need `cargo nextest` for its one-process-per execution execution model
# since we can only boot the VM once per process. Normal `cargo test`
# runs tests in threads and can't handle this.
#
# On darwin, it's available through `brew install cargo-nextest`. See
# https://nexte.st/docs/installation/pre-built-binaries/ otherwise.
zjit-test: libminiruby.a
	RUBY_BUILD_DIR='$(TOP_BUILD_DIR)' \
	    RUBY_LD_FLAGS='$(LDFLAGS) $(XLDFLAGS) $(MAINLIBS)' \
	    CARGO_TARGET_DIR='$(ZJIT_CARGO_TARGET_DIR)' \
	    $(CARGO) nextest run --manifest-path '$(top_srcdir)/zjit/Cargo.toml' $(ZJIT_TESTS)

# Run a ZJIT test written with Rust #[test] under LLDB
zjit-test-lldb: libminiruby.a
	$(Q)set -eu; \
	    if [ -z '$(ZJIT_TESTS)' ]; then \
		echo "Please pass a ZJIT_TESTS=... filter to make."; \
		echo "Many tests only work when it's the only test in the process."; \
		exit 1; \
	    fi; \
	    exe_path=`RUBY_BUILD_DIR='$(TOP_BUILD_DIR)' \
	    RUBY_LD_FLAGS='$(LDFLAGS) $(XLDFLAGS) $(MAINLIBS)' \
	    CARGO_TARGET_DIR='$(ZJIT_CARGO_TARGET_DIR)' \
	    $(CARGO) nextest list --manifest-path '$(top_srcdir)/zjit/Cargo.toml' --message-format json --list-type=binaries-only | \
	    $(BASERUBY) -rjson -e 'puts JSON.load(STDIN.read).dig("rust-binaries", "zjit", "binary-path")'`; \
	    exec lldb $$exe_path -- --test-threads=1 $(ZJIT_TESTS)

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
endif
