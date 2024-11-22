# frozen_string_literal: true

require "mkmf"

srcdir = File.join(__dir__, "..")
$CFLAGS << " -I#{srcdir}"

$CFLAGS << " -DBUILDING_SHARED_GC"
$CFLAGS << " -fPIC"

def create_gc_makefile(name)
  create_makefile("librubygc.#{name}")
end
