#!ruby -s

require 'mkmf'
require 'rbconfig'

def main
  unless have_command('bison')
    $stderr.puts 'Ripper requires bison; abort'
    exit 1
  end
  $objs = %w(ripper.o)
  $cleanfiles.concat %w(ripper.y ripper.c ripper.output ids1 ids2)
  $CPPFLAGS += ' -DRIPPER'
  $CPPFLAGS += ' -DRIPPER_DEBUG' if $debug
  create_makefile 'ripper'
end

def have_command(cmd)
  ENV['PATH'].split(File::PATH_SEPARATOR).any? {|path|
    File.executable?("#{path}/#{cmd}#{Config::CONFIG['EXEEXT']}")
  }
end

main
