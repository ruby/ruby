# -*- mode: makefile-gmake; indent-tabs-mode: t -*-

YJIT_SRC_FILES = $(wildcard \
	$(top_srcdir)/yjit/Cargo.* \
	$(top_srcdir)/yjit/src/*.rs \
	$(top_srcdir)/yjit/src/*/*.rs \
	$(top_srcdir)/yjit/src/*/*/*.rs \
	$(top_srcdir)/yjit/src/*/*/*/*.rs \
	$(top_srcdir)/jit/src/lib.rs \
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

RUST_VERSION = +1.58.0

# Gives quick feedback about YJIT. Not a replacement for a full test run.
.PHONY: yjit-check
yjit-check:
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
