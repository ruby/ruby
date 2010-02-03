require 'mkmf'

if RbConfig::CONFIG['GCC'] == 'yes'
  $CFLAGS << " -fno-defer-pop -fno-omit-frame-pointer"
end

$INSTALLFILES = [
  ["dl.h", "$(HDRDIR)"],
]

if pkg_config("libffi")
  # libffi closure api must be switched depending on the version
  if system("pkg-config --atleast-version=3.0.9 libffi")
    $defs.push(format('-DUSE_NEW_CLOSURE_API'))
  end
else
  dir_config('ffi', '/usr/include', '/usr/lib')
end

unless have_header('ffi.h')
  if have_header('ffi/ffi.h')
    $defs.push(format('-DUSE_HEADER_HACKS'))
  else
    abort "ffi is missing"
  end
end

unless have_library('ffi')
  abort "ffi is missing"
end

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
