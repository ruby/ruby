#----------------------------------
# extconf.rb
# $Revision$
#----------------------------------
require 'mkmf'

case RUBY_PLATFORM
when /cygwin/
  inc = nil
  lib = '/usr/lib/w32api'
end

dir_config("win32", inc, lib)

SRCFILES=<<SRC
win32ole.c
SRC

def create_docfile(src)
  open(File.expand_path($srcdir) + "/.document", "w") {|ofs|
    ofs.print src
  }
end

def create_win32ole_makefile
  if have_library("ole32") and
     have_library("oleaut32") and
     have_library("uuid", "&CLSID_CMultiLanguage", "mlang.h") and
     have_library("user32") and
     have_library("kernel32") and
     have_library("advapi32") and
     have_header("windows.h")
    unless have_type("IMultiLanguage2", "mlang.h")
      have_type("IMultiLanguage", "mlang.h")
    end
    create_makefile("win32ole")
    create_docfile(SRCFILES)
  else
    create_docfile("")
  end
end


case RUBY_PLATFORM
when /mswin/
  $CFLAGS += ' /W3'
end
create_win32ole_makefile
