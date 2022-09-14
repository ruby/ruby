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

# YJIT_SUPPORT=yes when `configure` gets `--enable-yjit`
ifeq ($(YJIT_SUPPORT),yes)
$(YJIT_LIBS): $(YJIT_SRC_FILES)
	$(ECHO) 'building Rust YJIT (release mode)'
	$(Q) $(RUSTC) \
	        --crate-name=yjit \
	        --crate-type=staticlib \
	        --edition=2021 \
	        -C opt-level=3 \
	        -C overflow-checks=on \
	        '--out-dir=$(CARGO_TARGET_DIR)/release/' \
	        $(top_srcdir)/yjit/src/lib.rs
	touch $@
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
	touch $@
else
endif

# Put this here instead of in common.mk to avoid breaking nmake builds
# TODO: might need to move for BSD Make support
miniruby$(EXEEXT): $(YJIT_LIBS)

# Generate Rust bindings. See source for details.
# Needs `./configure --enable-yjit=dev` and Clang.
ifneq ($(strip $(CARGO)),) # if configure found Cargo
.PHONY: yjit-bindgen yjit-bindgen-show-unused
yjit-bindgen: yjit.$(OBJEXT)
	YJIT_SRC_ROOT_PATH='$(top_srcdir)' $(CARGO) run --manifest-path '$(top_srcdir)/yjit/bindgen/Cargo.toml' -- $(CFLAGS) $(XCFLAGS) $(CPPFLAGS)

check-yjit-bindgen-unused: yjit.$(OBJEXT)
	RUST_LOG=warn YJIT_SRC_ROOT_PATH='$(top_srcdir)' $(CARGO) run --manifest-path '$(top_srcdir)/yjit/bindgen/Cargo.toml' -- $(CFLAGS) $(XCFLAGS) $(CPPFLAGS) 2>&1 | (! grep "unused option: --allow")

# For CI, check whether YJIT's FFI bindings are up-to-date.
check-yjit-bindings: check-yjit-bindgen-unused
	git -C "$(top_srcdir)" diff --exit-code yjit/src/cruby_bindings.inc.rs
endif
