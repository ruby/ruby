#!ruby -s
# frozen_string_literal: true

require 'mkmf'
require 'rbconfig'

def main
  $objs = %w(ripper.o)
  $distcleanfiles.concat %w(ripper.y ripper.c eventids1.c eventids2table.c)
  $cleanfiles.concat %w(ripper.E ripper.output y.output .eventids2-check)
  $defs << '-DRIPPER'
  $defs << '-DRIPPER_DEBUG' if $debug
  $VPATH << '$(topdir)' << '$(top_srcdir)'
  $INCFLAGS << ' -I$(topdir) -I$(top_srcdir)'
  create_makefile 'ripper'
end

main
