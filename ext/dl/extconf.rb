require 'mkmf'

if( RbConfig::CONFIG['CC'] =~ /gcc/ )
  $CFLAGS << " -fno-defer-pop -fno-omit-frame-pointer"
end

CALLBACKS = (0..8).map{|i| "callback-#{i}"}
CALLBACK_SRCS = CALLBACKS.map{|basename| "#{basename}.c"}
CALLBACK_OBJS = CALLBACKS.map{|basename| "#{basename}.o"}

$INSTALLFILES = [
  ["dl.h", "$(HDRDIR)"],
]
$distcleanfiles += [ "callback.h", *CALLBACK_SRCS ]


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

$objs = %w[ cfunc.o dl.o cptr.o handle.o ] + CALLBACK_OBJS

if check
  $defs << %[-DRUBY_VERSION=\\"#{RUBY_VERSION}\\"]
  create_makefile("dl")
end
