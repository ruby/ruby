case RUBY_PLATFORM
when /cygwin/,/mingw/
  $CFLAGS = "-fno-defer-pop -fno-omit-frame-pointer"
  create_makefile("Win32API")
when /win32/
  create_makefile("Win32API")
end
