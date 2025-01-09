# frozen_string_literal: true

require_relative "../extconf_base"

# Statically link `libmmtk_ruby.a`
$LIBS << " $(MMTK_BUILD)/libmmtk_ruby.#{RbConfig::CONFIG["LIBEXT"]}"

create_gc_makefile("mmtk")

makefile = File.read("Makefile")

makefile.prepend("MMTK_BUILD=debug\n")

# Add `libmmtk_ruby.a` as an object file
makefile.gsub!(/^OBJS = (.*)$/, "OBJS = \\1 $(MMTK_BUILD)/libmmtk_ruby.#{RbConfig::CONFIG["LIBEXT"]}")

# Modify the `all` target to run the `libmmtk_ruby.a` target first
makefile.gsub!(/^all:\s+(.*)$/, "all: $(MMTK_BUILD)/libmmtk_ruby.#{RbConfig::CONFIG["LIBEXT"]} \\1")

# Add the `libmmtk_ruby.a` target to run `cargo build`
makefile << <<~MAKEFILE
  $(MMTK_BUILD)/libmmtk_ruby.#{RbConfig::CONFIG["LIBEXT"]}: $(wildcard $(srcdir)/src/*.rs) $(srcdir)/Cargo.toml $(srcdir)/Cargo.toml
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
