#!ruby -s

require 'mkmf'
require 'rbconfig'

def main
  unless find_executable('bison')
    unless File.exist?('ripper.c') or File.exist?("#{$srcdir}/ripper.c")
      $stderr.puts 'missing bison; abort'
      exit 1
    end
  end
  $objs = %w(ripper.o)
  $cleanfiles.concat %w(ripper.y ripper.c ripper.E ripper.output eventids1.c ids1 ids2)
  $CPPFLAGS += ' -DRIPPER'
  $CPPFLAGS += ' -DRIPPER_DEBUG' if $debug
  create_makefile 'ripper'
end

main
