# frozen_string_literal: true

require_relative "../extconf_base"

# Statically link `libmmtk_ruby.a`
$LIBS << " $(MMTK_BUILD)/$(LIBMMTK_RUBY)"

rustsrcs = Dir.glob("src/*.rs", base: __dir__).map {|s| "$(srcdir)/#{s}"}

create_gc_makefile("mmtk") do |makefile|
  [
    *makefile,

    <<~MAKEFILE,
    MMTK_BUILD = debug
    LIBMMTK_RUBY = libmmtk_ruby.#$LIBEXT
    RUSTSRCS = #{rustsrcs.join(" \\\n\t   ")}

    ifeq ($(MMTK_BUILD), debug)
    CPPFLAGS += -DMMTK_DEBUG
    endif
    MAKEFILE
  ]
end
