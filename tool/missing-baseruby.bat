: "
@echo off || (
  :warn
    echo>&2.%~1
  goto :eof
  :abort
    exit /b 1
)
: "
: ; call:warn() { echo "$1" >&2; }
: ; call:abort () { exit 1; }

call:warn "executable host ruby is required.  use --with-baseruby option."
call:warn "Note that BASERUBY must be Ruby 2.7.0 or later."
call:abort
