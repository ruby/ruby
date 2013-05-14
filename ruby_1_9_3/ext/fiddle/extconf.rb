require 'mkmf'

# :stopdoc:

dir_config 'libffi'

pkg_config("libffi")
unless have_header('ffi.h')
  if have_header('ffi/ffi.h')
    $defs.push(format('-DUSE_HEADER_HACKS'))
  else
    raise "ffi.h is missing. Please install libffi."
  end
end

unless have_library('ffi') || have_library('libffi')
  raise "libffi is missing. Please install libffi."
end

have_header 'sys/mman.h'

if have_header "dlfcn.h"
  have_library "dl"

  %w{ dlopen dlclose dlsym }.each do |func|
    abort "missing function #{func}" unless have_func(func)
  end

  have_func "dlerror"
elsif have_header "windows.h"
  %w{ LoadLibrary FreeLibrary GetProcAddress }.each do |func|
    abort "missing function #{func}" unless have_func(func)
  end
end

have_const('FFI_STDCALL', 'ffi.h') || have_const('FFI_STDCALL', 'ffi/ffi.h')

config = File.read(RbConfig.expand(File.join($arch_hdrdir, "ruby/config.h")))
types = {"SIZE_T"=>"SSIZE_T", "PTRDIFF_T"=>nil, "INTPTR_T"=>nil}
types.each do |type, signed|
  if /^\#define\s+SIZEOF_#{type}\s+(SIZEOF_(.+)|\d+)/ =~ config
    if size = $2 and size != 'VOIDP'
      size = types.fetch(size) {size}
      $defs << format("-DTYPE_%s=TYPE_%s", signed||type, size)
    end
    if signed
      check_signedness(type.downcase, "stddef.h")
    end
  end
end

create_makefile 'fiddle'

# :startdoc:
