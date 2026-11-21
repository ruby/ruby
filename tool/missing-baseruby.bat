:"" == "
@echo off || (
  :warn
    echo>&2.%~1
  goto :eof
  :abort
    exit /b 1
)||(
:)"||(
  # necessary libraries
  require 'erb'
  require 'fileutils'
  require 'tempfile'
  s = %^#
)
: ; call() { local call=${1#:}; shift; $call "$@"; }
: ; warn() { echo "$1" >&2; }
: ; abort () { exit 1; }

call :warn "executable host ruby is required.  use --with-baseruby option."
call :warn "Note that BASERUBY must be Ruby 3.1.0 or later."
call :abort
(goto :eof ^;)
verbose = true if ARGV[0] == "--verbose"
case
when !defined?(RubyVM::InstructionSequence)
  abort(*(["BASERUBY must be CRuby"] if verbose))
when RUBY_VERSION < s[%r[warn .*\KBASERUBY .*Ruby ([\d.]+)(?:\.0)?.*(?=\")],1]
  abort(*(["#{$&}. Found: #{RUBY_VERSION}"] if verbose))
end
