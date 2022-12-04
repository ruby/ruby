#!ruby -s
# frozen_string_literal: true

require 'mkmf'
require 'rbconfig'

def main
  yacc = ENV["YACC"] || "bison"

  unless find_executable(yacc)
    unless File.exist?('ripper.c') or File.exist?("#{$srcdir}/ripper.c")
      raise 'missing bison; abort'
    end
  end
  $objs = %w(ripper.o)
  $distcleanfiles.concat %w(ripper.y ripper.c eventids1.c eventids2table.c)
  $cleanfiles.concat %w(ripper.E ripper.output y.output .eventids2-check)
  $defs << '-DRIPPER'
  $defs << '-DRIPPER_DEBUG' if $debug
  $VPATH << '$(topdir)' << '$(top_srcdir)'
  $INCFLAGS << ' -I$(topdir) -I$(top_srcdir)'
  create_makefile 'ripper' do |conf|
    conf << "BISON = #{yacc}"
  end
end

main
