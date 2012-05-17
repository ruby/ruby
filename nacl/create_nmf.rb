#!/usr/bin/ruby
# Copyright:: Copyright 2012 Google Inc.
# License:: All Rights Reserved.
# Original Author:: Yugui Sonoda (mailto:yugui@google.com)
#
# Wrapper for create_nmf.py / generate_nmf.py

require File.join(File.dirname(__FILE__), 'nacl-config')

include NaClConfig
$verbosity = 0

def usage_and_exit
  $stderr.puts "Usage: #{$PROGRAM_NAME} [--verbose=N] path/to/input.nexe path/to/output.nmf"
  exit false
end

def create_dynamically_linked(nmf, exe)
  cmd = [
    PYTHON, CREATE_NMF,
    '-o', nmf,
    '-D', OBJDUMP,
    '-L', HOST_LIB,
    exe
  ]
  puts cmd.join(' ') if $verbosity > 0
  exec(*cmd)
end

def create_statically_linked(nmf, exe)
  File.open(nmf, "w") {|f|
    f.write <<-EOS.gsub(/^ {6}/, '')
      {
        "program": {
          "#{ARCH}": {
            "url": "#{exe}"
          }
        }
      }
    EOS
  }
end

def main
  while m = ARGV.first.match(/--([a-z-]+)(?:=(\S+))?/)
    case m[1]
    when 'verbose'
      usage_and_exit unless m[2][/\A[0-9]+\z/]
      $verbosity = m[2].to_i
    when 'help'
      usage_end_exit
    end
    ARGV.shift
  end

  usage_and_exit if ARGV.size < 2

  exe, nmf = ARGV[0], ARGV[1]
  if newlib?
    create_statically_linked(nmf, exe)
  else
    create_dynamically_linked(nmf, exe)
  end
end

if __FILE__ == $0
   main()
end


