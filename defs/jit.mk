# Make recipes that deal with the rust code of YJIT and ZJIT.

# Because of Cargo cache, if the actual binary is not changed from the
# previous build, the mtime is preserved as the cached file.
# This means the target is not updated actually, and it will need to
# rebuild at the next build.
RUST_LIB_TOUCH = touch $@

ifneq ($(JIT_CARGO_SUPPORT),no)
$(RUST_LIB):
	$(Q)if [ '$(ZJIT_SUPPORT)' != no -a '$(YJIT_SUPPORT)' != no ]; then \
	    echo 'building YJIT and ZJIT ($(JIT_CARGO_SUPPORT:yes=release) mode)'; \
	elif [ '$(ZJIT_SUPPORT)' != no ]; then \
	    echo 'building ZJIT ($(JIT_CARGO_SUPPORT) mode)'; \
	elif [ '$(YJIT_SUPPORT)' != no ]; then \
	    echo 'building YJIT ($(JIT_CARGO_SUPPORT) mode)'; \
	fi
	+$(Q)CARGO_TARGET_DIR='$(CARGO_TARGET_DIR)' \
	    CARGO_TERM_PROGRESS_WHEN='never' \
	    $(CARGO) $(CARGO_VERBOSE) build --manifest-path '$(top_srcdir)/Cargo.toml' $(CARGO_BUILD_ARGS)
	$(RUST_LIB_TOUCH)
endif

RUST_LIB_SYMBOLS = $(RUST_LIB:.a=).symbols
$(RUST_LIBOBJ): $(RUST_LIB)
	$(ECHO) 'partial linking $(RUST_LIB) into $@'
ifneq ($(findstring darwin,$(target_os)),)
	$(Q) $(CC) -nodefaultlibs -r -o $@ -exported_symbols_list $(RUST_LIB_SYMBOLS) $(RUST_LIB)
else
	$(Q) $(LD) -r -o $@ --whole-archive $(RUST_LIB)
	-$(Q) $(OBJCOPY) --wildcard --keep-global-symbol='$(SYMBOL_PREFIX)rb_*' $(@)
endif

rust-libobj: $(RUST_LIBOBJ)
rust-lib: $(RUST_LIB)

# For Darwin only: a list of symbols that we want the glommed Rust static lib to export.
# Unfortunately, using wildcard like '_rb_*' with -exported-symbol does not work, at least
# not on version 820.1. Assume llvm-nm, so XCode 8.0 (from 2016) or newer.
#
# The -exported_symbols_list pulls out the right archive members. Symbols not listed
# in the list are made private extern, which are in turn made local as we're using `ld -r`.
# Note, section about -keep_private_externs in ld's man page hints at this behavior on which
# we rely.
ifneq ($(findstring darwin,$(target_os)),)
$(RUST_LIB_SYMBOLS): $(RUST_LIB)
	$(Q) $(tooldir)/darwin-ar $(NM) --defined-only --extern-only $(RUST_LIB) | \
	sed -n -e 's/.* //' -e '/^$(SYMBOL_PREFIX)rb_/p' \
	-e '/^$(SYMBOL_PREFIX)rust_eh_personality/p' \
	> $@

$(RUST_LIBOBJ): $(RUST_LIB_SYMBOLS)
endif
