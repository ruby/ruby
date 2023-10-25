# This file is included into the Makefile when
# we're *not* using GNU make. Stick to basic features.

# Rebuild every time since we don't want to list Rust source
# file dependencies.
.PHONY: yjit-static-lib
$(YJIT_LIBS): yjit-static-lib
	$(empty)

yjit-static-lib:
	$(ECHO) 'building Rust YJIT (release mode)'
	$(Q) $(RUSTC) $(YJIT_RUSTC_ARGS)

# Assume GNU flavor LD and OBJCOPY. Works on FreeBSD 13, at least.
$(YJIT_LIBOBJ): $(YJIT_LIBS)
	$(ECHO) 'partial linking $(YJIT_LIBS) into $@'
	$(Q) $(LD) -r -o $@ --whole-archive $(YJIT_LIBS)
	-$(Q) $(OBJCOPY) --wildcard --keep-global-symbol='$(SYMBOL_PREFIX)rb_*' $(@)
