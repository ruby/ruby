if PLATFORM =~ /win32/i
  $:.unshift '../..'
  require 'rbconfig'
  include Config
  $CFLAGS = "-fno-defer-pop" if /gcc/ =~ CONFIG['CC']
  create_makefile("Win32API")
end
