# Make rules for core_rs, the Ruby on Rust core crate.
#
# Included only when configure enabled the Rust ports (USE_RUST_PORTS=1):
# from defs/gmake.mk under GNU make, and appended to the Makefile by
# configure otherwise.  Stick to POSIX make features.
#
# core_rs is built with rustc alone (no cargo, no network) as a no_std
# staticlib, then partially linked into a single object that joins
# COMMONOBJS.  Only `rb_*` and `ruby_*` symbols stay global.

# Keep in sync with core_rs/src/.
CORE_RS_SRCS = $(srcdir)/core_rs/src/lib.rs \
	$(srcdir)/core_rs/src/alloc.rs \
	$(srcdir)/core_rs/src/complex.rs \
	$(srcdir)/core_rs/src/ffi/mod.rs \
	$(srcdir)/core_rs/src/ffi/alloc.rs \
	$(srcdir)/core_rs/src/ffi/api.rs \
	$(srcdir)/core_rs/src/ffi/api/non_raising.rs \
	$(srcdir)/core_rs/src/ffi/api/raising.rs \
	$(srcdir)/core_rs/src/ffi/protect.rs \
	$(srcdir)/core_rs/src/ffi/value.rs \
	$(srcdir)/core_rs/src/re.rs \
	$(srcdir)/core_rs/src/util.rs \
	$(empty)

# rustc --cfg options that mirror the C configuration core_rs/src/ffi/
# depends on.  They are taken from the C preprocessor with the same flags as
# the C sources (core_rs/cfg.c), so overrides such as cppflags=-DUSE_FLONUM=0
# reach the Rust side too.  Prints nothing (and the rustc build then stops
# with a compile_error!) if the preprocessor fails.
CORE_RS_CFG = $(CPP) $(XCFLAGS) $(CPPFLAGS) $(srcdir)/core_rs/cfg.c | \
	sed -n -e 's/^core_rs_cfg_use_flonum 1$$/--cfg core_rs_flonum/p' \
	       -e 's/^core_rs_cfg_use_flonum 0$$/--cfg core_rs_no_flonum/p' \
	       -e 's/^core_rs_cfg_\([a-z0-9_]*\) \(.*\)$$/--cfg core_rs_\1="\2"/p'

$(CORE_RS_LIB): $(CORE_RS_SRCS) $(srcdir)/core_rs/cfg.c
	$(ECHO) 'building core_rs (Rust ports)'
	$(Q) $(MAKEDIRS) $(TOP_BUILD_DIR)/target/core_rs
	$(gnumake_recursive)$(Q) $(RUSTC) --crate-name=core_rs --crate-type=staticlib --edition=2024 \
	    $(CORE_RS_RUSTC_FLAGS) `$(CORE_RS_CFG)` \
	    -o $(CORE_RS_LIB) \
	    $(srcdir)/core_rs/src/lib.rs

$(CORE_RS_OBJ): $(CORE_RS_LIB)
	$(ECHO) 'partial linking core_rs into $@'
	$(Q) $(CORE_RS_PARTIAL_LINK)

core-rs: $(CORE_RS_OBJ)

# Unit tests for the pure parts of core_rs (needs only rustc; std is used
# by the test harness, the library itself stays no_std).
core-rs-test:
	$(Q) $(MAKEDIRS) $(TOP_BUILD_DIR)/target/core_rs
	$(Q) $(RUSTC) --crate-name=core_rs --edition=2024 --test \
	    `$(CORE_RS_CFG)` \
	    -o $(TOP_BUILD_DIR)/target/core_rs/core_rs-test \
	    $(srcdir)/core_rs/src/lib.rs
	$(Q) $(TOP_BUILD_DIR)/target/core_rs/core_rs-test

# Internal (rb_core_*) exports of core_rs must stay out of libruby's dynamic
# symbol table (internal/core_rs.h).  Fails if any of them is visible.
core-rs-check-hidden: $(LIBRUBY_SO)
	$(Q) if $(NM) -D --defined-only $(LIBRUBY_SO) | grep ' rb_core_'; then \
	    echo 'core_rs: rb_core_* symbols are exported from $(LIBRUBY_SO); declare them in internal/core_rs.h' >&2; \
	    exit 1; \
	fi
	$(Q) echo 'core_rs: no rb_core_* symbol is exported from $(LIBRUBY_SO)'

# Check C fallback compilation for ported functions (#if !USE_RUST_PORTS)
core-rs-check-fallbacks:
	$(Q) $(BASERUBY) -I$(srcdir)/tool $(srcdir)/tool/generate_porting_ledger.rb --check-fallbacks

# Re-measure and update the function inventory baseline snapshot
core-rs-inventory:
	$(Q) $(BASERUBY) -I$(srcdir)/tool $(srcdir)/tool/core_rs/inventory.rb --snapshot > $(srcdir)/docs/ruby_on_rust/inventory-snapshot.tsv


