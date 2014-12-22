require 'mkmf'

# :stopdoc:

if ! enable_config('bundled-libffi', false)
  dir_config 'libffi'

  pkg_config("libffi")
  ver = pkg_config("libffi", "modversion")

  if have_header(ffi_header = 'ffi.h')
    true
  elsif have_header(ffi_header = 'ffi/ffi.h')
    $defs.push(format('-DUSE_HEADER_HACKS'))
    true
  end and (have_library('ffi') || have_library('libffi'))
end or
begin
  ver = Dir.glob("#{$srcdir}/libffi-*/")
        .map {|n| File.basename(n)}
        .max_by {|n| n.scan(/\d+/).map(&:to_i)}
  unless ver
    raise "missing libffi. Please install libffi."
  end

  ffi_header = 'ffi.h'
  libffi = Struct.new(*%I[dir srcdir builddir include lib a cflags opt arch]).new
  libffi.dir = ver
  if $srcdir == "."
    libffi.builddir = "#{ver}/#{RUBY_PLATFORM}"
    libffi.srcdir = "."
  else
    libffi.builddir = libffi.dir
    libffi.srcdir = relative_from("#{$srcdir}/#{ver}", "..")
  end
  libffi.include = "#{libffi.builddir}/include"
  libffi.lib = "#{libffi.builddir}/.libs"
  libffi.a = "#{libffi.lib}/libffi.#{$LIBEXT}"
  libffi.cflags = RbConfig.expand("$(CFLAGS)", CONFIG.merge("warnflags"=>""))
  ver = ver[/libffi-(.*)/, 1]

  FileUtils.mkdir_p(libffi.dir)
  libffi.opt = CONFIG['configure_args'][/'(-C)'/, 1]
  libffi.arch = RbConfig::CONFIG['host']
  args = %W[
    #{libffi.srcdir}/configure #{libffi.opt}
    --disable-shared
    --host=#{libffi.arch} --enable-builddir=#{RUBY_PLATFORM}
      CC=#{RbConfig::CONFIG['CC']} CFLAGS=#{libffi.cflags}
  ]

  Logging::open do
    Logging.message("%p in %s\n", args, libffi.dir)
    system(*args, chdir: libffi.dir) or
      raise "failed to configure libffi. Please install libffi."
  end
  $INCFLAGS << " -I" << libffi.include
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

have_const('FFI_STDCALL', ffi_header)

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

if libffi
  $LIBPATH.unshift libffi.lib
  $LOCAL_LIBS.prepend("#{libffi.a} ").strip!
end
create_makefile 'fiddle' do |conf|
  next conf unless libffi
  if $gnumake
    submake = "$(MAKE) -C $(LIBFFI_DIR)\n"
  else
    submake = "cd $(LIBFFI_DIR) && \\\n\t\t" << "#{config_string("exec")} $(MAKE)".strip
  end
  sep = "/"
  seprpl = config_string('BUILD_FILE_SEPARATOR') {|s| sep = s; ":/=#{s}" if s != "/"} || ""
  conf << <<-MK.gsub(/^ +| +$/, '')
   PWD =
   LIBFFI_CONFIGURE = $(LIBFFI_SRCDIR#{seprpl})#{sep}configure #{libffi.opt}
   LIBFFI_ARCH = #{libffi.arch}
   LIBFFI_SRCDIR = #{libffi.srcdir}
   LIBFFI_DIR = #{libffi.dir}
   LIBFFI_A = #{libffi.a}
   LIBFFI_CFLAGS = #{libffi.cflags}
   FFI_H = $(LIBFFI_DIR)/include/ffi.h
   SUBMAKE_LIBFFI = #{submake}
  MK
end

if libffi
  $LIBPATH.pop
  $LOCAL_LIBS.prepend("ext/fiddle/")
end

# :startdoc:
