require 'mkmf'

# :stopdoc:

if ! enable_config('bundled-libffi', false)
  dir_config 'libffi'

  pkg_config("libffi")
  ver = pkg_config("libffi", "modversion")

  if have_header('ffi.h')
    true
  elsif have_header('ffi/ffi.h')
    $defs.push(format('-DUSE_HEADER_HACKS'))
    true
  end and (have_library('ffi') || have_library('libffi'))
end or
begin
  ver = Dir.glob("#{$srcdir}/libffi-*/")
        .map {|n| File.basename(n)}
        .max_by {|n| n.scan(/\d+/).map(&:to_i)}
  bundled = ver
  if $srcdir == "."
    builddir = "#{ver}/#{RUBY_PLATFORM}"
    libffi_srcdir = "."
  else
    builddir = bundled
    libffi_srcdir = relative_from("#{$srcdir}/#{bundled}", "..")
  end
  libffi_include = "#{builddir}/include"
  libffi_lib = "#{builddir}/.libs"
  libffi_a = "#{libffi_lib}/libffi.#{$LIBEXT}"
  libffi_cflags = RbConfig.expand("$(CFLAGS)", CONFIG.merge("warnflags"=>""))
  $LIBPATH.unshift libffi_lib
  $INCFLAGS << " -I" << libffi_include
  ver = ver[/libffi-(.*)/, 1]
end

if ver
  ver = ver.gsub(/-rc\d+/, '') # If ver contains rc version, just ignored.
  ver = (ver.split('.') + [0,0])[0,3]
  $defs.push(%{-DRUBY_LIBFFI_MODVERSION=#{ '%d%03d%03d' % ver }})
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

create_makefile 'fiddle' do |conf|
  if $gnumake
    submake = "$(MAKE) -C $(LIBFFI_DIR)\n"
  else
    submake = "cd $(LIBFFI_DIR) && \\\n\t\t" << "#{config_string("exec")} $(MAKE)".strip
  end
  sep = "/"
  seprpl = config_string('BUILD_FILE_SEPARATOR') {|s| sep = s; ":/=#{s}" if s != "/"} || ""
  conf << <<-MK.gsub(/^ +/, '')
   PWD =
   LIBFFI_CONFIGURE = $(LIBFFI_SRCDIR#{seprpl})#{sep}configure#{/'-C'/ =~ CONFIG['configure_args'] ? ' -C' : ''}
   LIBFFI_ARCH = #{RbConfig::CONFIG['arch'].sub(/\Ax64-(?=mingw|mswin)/, 'x86_64-')}
   LIBFFI_SRCDIR = #{libffi_srcdir}
   LIBFFI_DIR = #{bundled}
   LIBFFI_A = #{libffi_a}
   LIBFFI_CFLAGS = #{libffi_cflags}
   FFI_H = #{bundled && '$(LIBFFI_DIR)/include/ffi.h'}
   SUBMAKE_LIBFFI = #{submake}
  MK
end

if bundled
  args = [$make, *sysquote($mflags)]
  Logging::open do
    Logging.message("%p\n", args)
    system(*args) or
      raise "failed to configure libffi. Please install libffi."
  end
end

# :startdoc:
