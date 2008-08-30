require 'mkmf'

if( RbConfig::CONFIG['CC'] =~ /gcc/ )
  $CFLAGS << " -fno-defer-pop -fno-omit-frame-pointer"
end

$INSTALLFILES = [
  ["dl.h", "$(HDRDIR)"],
]
$distcleanfiles << "callback.h"


check = true
if( have_header("dlfcn.h") )
  have_library("dl")
  check &&= have_func("dlopen")
  check &&= have_func("dlclose")
  check &&= have_func("dlsym")
  have_func("dlerror")
elsif( have_header("windows.h") )
  check &&= have_func("LoadLibrary")
  check &&= have_func("FreeLibrary")
  check &&= have_func("GetProcAddress")
else
  check = false
end

$objs = %w[
  cfunc.o dl.o cptr.o handle.o
  callback-0.o callback-1.o callback-2.o callback-3.o
  callback-4.o callback-5.o callback-6.o callback-7.o
  callback-8.o
]

if check
  $defs << %[-DRUBY_VERSION=\\"#{RUBY_VERSION}\\"]
  create_makefile("dl")
end
