#!ruby -s
# frozen_string_literal: true

require 'mkmf'
require 'rbconfig'

def main
  $objs = %w(eventids1.o eventids2.o ripper.o ripper_init.o)
  $distcleanfiles.concat %w(ripper.y ripper.c eventids1.c eventids1.h eventids2table.c ripper_init.c)
  $cleanfiles.concat %w(ripper.E ripper.output y.output .eventids2-check)
  $defs << '-DRIPPER'
  $defs << '-DRIPPER_DEBUG' if $debug
  $VPATH << '$(topdir)' << '$(top_srcdir)'
  $INCFLAGS << ' -I$(topdir) -I$(top_srcdir)'
  create_makefile 'ripper'
end

main
