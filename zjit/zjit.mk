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
$(ZJIT_LIBS): $(ZJIT_SRC_FILES)
	$(ECHO) 'building Rust ZJIT ($(ZJIT_SUPPORT) mode)'
	+$(Q)$(CHDIR) $(top_srcdir)/zjit && \
	        CARGO_TARGET_DIR='$(ZJIT_CARGO_TARGET_DIR)' \
	        CARGO_TERM_PROGRESS_WHEN='never' \
	        $(CARGO) $(CARGO_VERBOSE) build $(CARGO_BUILD_ARGS)
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

RUST_VERSION = +1.58.0

# Gives quick feedback about ZJIT. Not a replacement for a full test run.
.PHONY: zjit-smoke-test
zjit-smoke-test:
ifneq ($(strip $(CARGO)),)
	$(CARGO) $(RUST_VERSION) test --all-features -q --manifest-path='$(top_srcdir)/zjit/Cargo.toml'
endif
	$(MAKE) btest RUN_OPTS='--zjit-call-threshold=1' BTESTS=-j
	$(MAKE) test-all TESTS='$(top_srcdir)/test/ruby/test_zjit.rb'

ZJIT_BINDGEN_DIFF_OPTS =

# Generate Rust bindings. See source for details.
# Needs `./configure --enable-zjit=dev` and Clang.
ifneq ($(strip $(CARGO)),) # if configure found Cargo
.PHONY: zjit-bindgen zjit-bindgen-show-unused
zjit-bindgen: zjit.$(OBJEXT)
	ZJIT_SRC_ROOT_PATH='$(top_srcdir)' $(CARGO) run --manifest-path '$(top_srcdir)/zjit/bindgen/Cargo.toml' -- $(CFLAGS) $(XCFLAGS) $(CPPFLAGS)
	$(Q) if [ 'x$(HAVE_GIT)' = xyes ]; then $(GIT) -C "$(top_srcdir)" diff $(ZJIT_BINDGEN_DIFF_OPTS) zjit/src/cruby_bindings.inc.rs; fi

check-zjit-bindgen-unused: zjit.$(OBJEXT)
	RUST_LOG=warn ZJIT_SRC_ROOT_PATH='$(top_srcdir)' $(CARGO) run --manifest-path '$(top_srcdir)/zjit/bindgen/Cargo.toml' -- $(CFLAGS) $(XCFLAGS) $(CPPFLAGS) 2>&1 | (! grep "unused option: --allow")
endif
