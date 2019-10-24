# frozen_string_literal: true
require 'mkmf'

# :stopdoc:

bundle = enable_config('bundled-libffi')
if ! bundle
  dir_config 'libffi'

  pkg_config("libffi") and
    ver = pkg_config("libffi", "modversion")

  if have_header(ffi_header = 'ffi.h')
    true
  elsif have_header(ffi_header = 'ffi/ffi.h')
    $defs.push(format('-DUSE_HEADER_HACKS'))
    true
  end and (have_library('ffi') || have_library('libffi'))
end or
begin
  # for https://github.com/ruby/fiddle
  if bundle && File.exist?("../../bin/extlibs.rb")
    require "fileutils"
    require_relative "../../bin/extlibs"
    extlibs = ExtLibs.new
    cache_dir = File.expand_path("../../tmp/.download_cache", $srcdir)
    ext_dir = File.expand_path("../../ext", $srcdir)
    Dir.glob("#{$srcdir}/libffi-*/").each{|dir| FileUtils.rm_rf(dir)}
    extlibs.run(["--cache=#{cache_dir}", ext_dir])
  end
  ver = bundle != false &&
        Dir.glob("#{$srcdir}/libffi-*/")
        .map {|n| File.basename(n)}
        .max_by {|n| n.scan(/\d+/).map(&:to_i)}
  unless ver
    raise "missing libffi. Please install libffi."
  end

  srcdir = "#{$srcdir}/#{ver}"
  ffi_header = 'ffi.h'
  libffi = Struct.new(*%I[dir srcdir builddir include lib a cflags ldflags opt arch]).new
  libffi.dir = ver
  if $srcdir == "."
    libffi.builddir = "#{ver}/#{RUBY_PLATFORM}"
    libffi.srcdir = "."
  else
    libffi.builddir = libffi.dir
    libffi.srcdir = relative_from(srcdir, "..")
  end
  libffi.include = "#{libffi.builddir}/include"
  libffi.lib = "#{libffi.builddir}/.libs"
  libffi.a = "#{libffi.lib}/libffi_convenience.#{$LIBEXT}"
  nowarn = CONFIG.merge("warnflags"=>"")
  libffi.cflags = RbConfig.expand("$(CFLAGS)".dup, nowarn)
  ver = ver[/libffi-(.*)/, 1]

  FileUtils.mkdir_p(libffi.dir)
  libffi.opt = CONFIG['configure_args'][/'(-C)'/, 1]
  libffi.ldflags = RbConfig.expand("$(LDFLAGS) #{libpathflag([relative_from($topdir, "..")])} #{$LIBRUBYARG}".dup)
  libffi.arch = RbConfig::CONFIG['host']
  if $mswin
    unless find_executable(as = /x64/ =~ libffi.arch ? "ml64" : "ml")
      raise "missing #{as} command."
    end
    $defs << "-DFFI_BUILDING"
    libffi_config = "#{relative_from($srcdir, '..')}/win32/libffi-config.rb"
    config = CONFIG.merge("top_srcdir" => $top_srcdir)
    args = $ruby.gsub(/:\/=\\/, '')
    args.gsub!(/\)\\/, ')/')
    args = args.shellsplit
    args.map! {|s| RbConfig.expand(s, config)}
    args << '-C' << libffi.dir << libffi_config
    opts = {}
  else
    args = %W[sh #{libffi.srcdir}/configure ]
    opts = {chdir: libffi.dir}
  end
  cc = RbConfig::CONFIG['CC']
  cxx = RbConfig::CONFIG['CXX']
  ld = RbConfig::CONFIG['LD']
  args.concat %W[
    --srcdir=#{libffi.srcdir}
    --host=#{libffi.arch}
    --enable-builddir=#{RUBY_PLATFORM}
  ]
  args << ($enable_shared || !$static ? '--enable-shared' : '--enable-static')
  args << libffi.opt if libffi.opt
  args.concat %W[
      CC=#{cc} CFLAGS=#{libffi.cflags}
      CXX=#{cxx} CXXFLAGS=#{RbConfig.expand("$(CXXFLAGS)".dup, nowarn)}
      LD=#{ld} LDFLAGS=#{libffi.ldflags}
  ]

  FileUtils.rm_f("#{libffi.include}/ffitarget.h")
  Logging::open do
    Logging.message("%p in %p\n", args, opts)
    unless system(*args, **opts)
      begin
        IO.copy_stream(libffi.dir + "/config.log", Logging.instance_variable_get(:@logfile))
      rescue SystemCallError => e
        Logfile.message("%s\n", e.message)
      end
      raise "failed to configure libffi. Please install libffi."
    end
  end
  if $mswin && File.file?("#{libffi.include}/ffitarget.h")
    FileUtils.rm_f("#{libffi.include}/ffitarget.h")
  end
  unless File.file?("#{libffi.include}/ffitarget.h")
    FileUtils.cp("#{srcdir}/src/x86/ffitarget.h", libffi.include, preserve: true)
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
  $LOCAL_LIBS.prepend("./#{libffi.a} ").strip! # to exts.mk
  $INCFLAGS.gsub!(/-I#{libffi.dir}/, '-I$(LIBFFI_DIR)')
end
$INCFLAGS << " -I$(top_srcdir)"
create_makefile 'fiddle' do |conf|
  if !libffi
    next conf << "LIBFFI_CLEAN = none\n"
  elsif $gnumake && !$nmake
    submake_arg = "-C $(LIBFFI_DIR)\n"
  else
    submake_pre = "cd $(LIBFFI_DIR) && #{config_string("exec")}".strip
  end
  if $nmake
    cmd = "$(RUBY) -C $(LIBFFI_DIR) #{libffi_config} --srcdir=$(LIBFFI_SRCDIR)"
  else
    cmd = "cd $(LIBFFI_DIR) && #$exec $(LIBFFI_SRCDIR)/configure #{libffi.opt}"
  end
  sep = "/"
  seprpl = config_string('BUILD_FILE_SEPARATOR') {|s| sep = s; ":/=#{s}" if s != "/"} || ""
  conf << <<-MK.gsub(/^ +| +$/, '')
   PWD =
   LIBFFI_CONFIGURE = #{cmd}
   LIBFFI_ARCH = #{libffi.arch}
   LIBFFI_SRCDIR = #{libffi.srcdir.sub(libffi.dir, '$(LIBFFI_DIR)')}
   LIBFFI_DIR = #{libffi.dir}
   LIBFFI_A = #{libffi.a.sub(libffi.dir, '$(LIBFFI_DIR)')}
   LIBFFI_CFLAGS = #{libffi.cflags}
   LIBFFI_LDFLAGS = #{libffi.ldflags}
   FFI_H = $(LIBFFI_DIR)/include/ffi.h
   SUBMAKE_PRE = #{submake_pre}
   SUBMAKE_ARG = #{submake_arg}
   LIBFFI_CLEAN = libffi
  MK
end

if libffi
  $LIBPATH.pop
end

# :startdoc:
