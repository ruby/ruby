:"" == "
@echo off || (
  :warn
    echo>&2.%~1
  goto :eof
  :abort
    exit /b 1
)||(
:)"||(
  s = %^#
)
: ; call() { local call=${1#:}; shift; $call "$@"; }
: ; warn() { echo "$1" >&2; }
: ; abort () { exit 1; }

call :warn "executable host ruby is required.  use --with-baseruby option."
call :warn "Note that BASERUBY must be Ruby 3.0.0 or later."
call :abort
: || (:^; abort if RUBY_VERSION < s[%r"warn .*Ruby ([\d.]+)(?:\.0)?",1])
