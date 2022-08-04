# -*- mode: makefile-gmake; indent-tabs-mode: t -*-

# Show Cargo progress when doing `make V=1`
CARGO_VERBOSE_0 = -q
CARGO_VERBOSE_1 =
CARGO_VERBOSE = $(CARGO_VERBOSE_$(V))

# Select between different build profiles with macro substitution
.PHONY: yjit-static-lib
yjit-static-lib: yjit-static-lib-$(YJIT_SUPPORT)

# YJIT_SUPPORT=yes when `configure` gets `--enable-yjit`
yjit-static-lib-yes:
	$(ECHO) 'building Rust YJIT (release mode)'
	$(Q) $(RUSTC) \
	        --crate-name=yjit \
	        --crate-type=staticlib \
	        --edition=2021 \
	        -C opt-level=3 \
	        -C overflow-checks=on \
	        '--out-dir=$(CARGO_TARGET_DIR)/release/' \
	        $(top_srcdir)/yjit/src/lib.rs

yjit-static-lib-no:
	$(ECHO) 'Error: Tried to build YJIT without configuring it first. Check `make showconfig`?'
	@false

yjit-static-lib-cargo:
	$(ECHO) 'building Rust YJIT ($(YJIT_SUPPORT) mode)'
	$(Q)$(CHDIR) $(top_srcdir)/yjit && \
	        CARGO_TARGET_DIR='$(CARGO_TARGET_DIR)' \
	        CARGO_TERM_PROGRESS_WHEN='never' \
	        $(CARGO) $(CARGO_VERBOSE) build $(CARGO_BUILD_ARGS)

yjit-static-lib-dev: yjit-static-lib-cargo
yjit-static-lib-dev_nodebug: yjit-static-lib-cargo
yjit-static-lib-stats: yjit-static-lib-cargo

# This PHONY prerequisite makes it so that we always run cargo. When there are
# no Rust changes on rebuild, Cargo does not touch the mtime of the static
# library and GNU make avoids relinking. $(empty) seems to be important to
# trigger rebuild each time in release mode.
$(YJIT_LIBS): yjit-static-lib
	$(empty)

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
