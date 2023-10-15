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

yjit-libobj: $(YJIT_LIBOBJ)

YJIT_LIB_SYMBOLS = $(YJIT_LIBS:.a=).symbols
$(YJIT_LIBOBJ): $(YJIT_LIBS)
	$(ECHO) 'partial linking $(YJIT_LIBS) into $@'
ifneq ($(findstring darwin,$(target_os)),)
	$(Q) $(CC) -nodefaultlibs -r -o $@ -exported_symbols_list $(YJIT_LIB_SYMBOLS) $(YJIT_LIBS)
else
	$(Q) $(LD) -r -o $@ --whole-archive $(YJIT_LIBS)
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
$(YJIT_LIB_SYMBOLS): $(YJIT_LIBS)
	$(Q) $(tooldir)/darwin-ar $(NM) --defined-only --extern-only $(YJIT_LIBS) | \
	sed -n -e 's/.* //' -e '/^$(SYMBOL_PREFIX)rb_/p' \
	-e '/^$(SYMBOL_PREFIX)rust_eh_personality/p' \
	> $@

$(YJIT_LIBOBJ): $(YJIT_LIB_SYMBOLS)
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
	$(CARGO) $(RUST_VERSION) test --all-features -q --manifest-path='$(top_srcdir)/yjit/Cargo.toml'
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
