#----------------------------------
# extconf.rb
# $Revision$
# $Date$
#----------------------------------
require 'mkmf'

dir_config("win32")
def create_win32ole_makefile
  if have_library("ole32") and
     have_library("oleaut32") and
     have_library("uuid") and 
     have_library("user32") and
     have_library("kernel32") and
     have_library("advapi32") and
     have_header("windows.h")
    create_makefile("win32ole")
  end
end

case RUBY_PLATFORM
when /mswin32/
  $CFLAGS += ' /W3'
when /cygwin/, /mingw/
  $defs << '-DNONAMELESSUNION'
end
create_win32ole_makefile
