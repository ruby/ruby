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

miniruby$(EXEEXT): $(YJIT_LIBS)
