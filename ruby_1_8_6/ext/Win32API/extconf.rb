require 'mkmf'

dir_config("win32")
if have_header("windows.h") and have_library("kernel32")
  create_makefile("Win32API")
end
