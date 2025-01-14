# frozen_string_literal: true

require "mkmf"

srcdir = File.join(__dir__, "..")
$INCFLAGS << " -I#{srcdir}"

$CPPFLAGS << " -DBUILDING_MODULAR_GC"

append_cflags("-fPIC")

def create_gc_makefile(name, &block)
  create_makefile("librubygc.#{name}", &block)
end
