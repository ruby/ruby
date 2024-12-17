# frozen_string_literal: true

require_relative "../extconf_base"

# Statically link `libmmtk_ruby.a`
$LIBS << " $(MMTK_BUILD)/libmmtk_ruby.#{RbConfig::CONFIG["LIBEXT"]}"

create_gc_makefile("mmtk")

makefile = File.read("Makefile")

# Modify the `all` target to run the `mmtk` target first
makefile.gsub!(/^all:\s+(.*)$/, 'all: mmtk \1')

# Add the `mmtk` target to run `cargo build`
makefile << <<~'MAKEFILE'
  $(srcdir)/mmtk.c: mmtk

  MMTK_BUILD=debug

  .PHONY: mmtk
  mmtk:
  	$(Q) case $(MMTK_BUILD) in \
  		release) \
  			CARGO_TARGET_DIR="." cargo build --manifest-path=$(srcdir)/Cargo.toml --release \
  			;; \
  		debug) \
  			CARGO_TARGET_DIR="." cargo build --manifest-path=$(srcdir)/Cargo.toml \
  			;; \
  		*) \
  			$(ECHO) Unknown MMTK_BUILD=$(MMTK_BUILD) \
  			exit 1 \
  			;; \
  	esac

  clean: clean-mmtk

  .PHONY: clean-mmtk
  clean-mmtk:
  	-$(Q)$(RM_RF) debug release
  	-$(Q)$(RM) .rustc_info.json
MAKEFILE

File.open("Makefile", "w") { |file| file.puts(makefile) }
