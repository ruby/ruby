# -*- mode: makefile-gmake; indent-tabs-mode: t -*-

# Show Cargo progress when doing `make V=1`
CARGO_VERBOSE_0 = -q
CARGO_VERBOSE_1 =
CARGO_VERBOSE = $(CARGO_VERBOSE_$(V))

# Select between different build profiles with macro substitution
.PHONY: yjit-static-lib
yjit-static-lib: yjit-static-lib-$(YJIT_SUPPORT)

YJIT_SRC_DIR = $(top_srcdir)/yjit/src
YJIT_SRCS := $(subst $(YJIT_SRC_DIR)/,yjit/src/,$(wildcard $(YJIT_SRC_DIR)/*.rs $(YJIT_SRC_DIR)/*/*.rs $(YJIT_SRC_DIR)/*/*/*.rs))

# YJIT_SUPPORT=yes when `configure` gets `--enable-yjit`
$(YJIT_LIBS): $(YJIT_SRCS)
ifeq ($(YJIT_SUPPORT),yes)
	$(ECHO) 'building Rust YJIT (release mode)'
	$(Q) $(RUSTC) \
	        --crate-name=yjit \
	        --crate-type=staticlib \
	        --edition=2021 \
	        -C opt-level=3 \
	        -C overflow-checks=on \
	        '--out-dir=$(CARGO_TARGET_DIR)/release/' \
	        $(top_srcdir)/yjit/src/lib.rs
else ifeq ($(YJIT_SUPPORT),no)
	$(ECHO) 'Error: Tried to build YJIT without configuring it first. Check `make showconfig`?'
	@false
else ifeq ($(YJIT_SUPPORT),dev)
	$(ECHO) 'building Rust YJIT (dev mode)'
	$(Q)$(CHDIR) $(top_srcdir)/yjit && \
	        CARGO_TARGET_DIR='$(CARGO_TARGET_DIR)' \
	        CARGO_TERM_PROGRESS_WHEN='never' \
	        $(CARGO) $(CARGO_VERBOSE) build $(CARGO_BUILD_ARGS)
endif

# Put this here instead of in common.mk to avoid breaking nmake builds
# TODO: might need to move for BSD Make support
miniruby$(EXEEXT): $(YJIT_LIBS)

# Generate Rust bindings. See source for details.
# Needs `./configure --enable-yjit=dev` and Clang.
ifneq ($(strip $(CARGO)),) # if configure found Cargo
.PHONY: yjit-bindgen
yjit-bindgen: yjit.$(OBJEXT)
	YJIT_SRC_ROOT_PATH='$(top_srcdir)' $(CARGO) run --manifest-path '$(top_srcdir)/yjit/bindgen/Cargo.toml' -- $(CFLAGS) $(XCFLAGS) $(CPPFLAGS)

# For CI, check whether YJIT's FFI bindings are up-to-date.
check-yjit-bindings: yjit-bindgen
	git -C "$(top_srcdir)" diff --exit-code yjit/src/cruby_bindings.inc.rs
endif
