case PLATFORM
when /cygwin/,/mingw/
  $CFLAGS = "-fno-defer-pop"
  create_makefile("Win32API")
when /win32/
  create_makefile("Win32API")
end
