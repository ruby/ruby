require 'mkmf'

if have_header("windows.h") and have_library("kernel32")
  if Config::CONFIG["CC"] =~ /gcc/
    $CFLAGS += "-fno-defer-pop -fno-omit-frame-pointer"
  end
  create_makefile("Win32API")
end
