case PLATFORM
when /cygwin32/,/mingw32/
  $CFLAGS = "-fno-defer-pop"
  create_makefile("Win32API")
when /win32/
  create_makefile("Win32API")
end
