require 'mkmf'

if RbConfig::CONFIG['GCC'] == 'yes'
  $CFLAGS << " -fno-defer-pop -fno-omit-frame-pointer"
end

$INSTALLFILES = [
  ["dl.h", "$(HDRDIR)"],
]

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

if check
  $defs << %[-DRUBY_VERSION=\\"#{RUBY_VERSION}\\"]
  create_makefile("dl")
end
