# frozen_string_literal: true
require 'mkmf'

# :stopdoc:

def gcc?
  RbConfig::CONFIG["GCC"] == "yes"
end

def disable_optimization_build_flag(flags)
  if gcc?
    expanded_flags = RbConfig.expand(flags.dup)
    optimization_option_pattern = /(^|\s)?-O\d(\s|$)?/
    if optimization_option_pattern.match?(expanded_flags)
      expanded_flags.gsub(optimization_option_pattern, '\\1-Og\\2')
    else
      flags + " -Og"
    end
  else
    flags
  end
end

def enable_debug_build_flag(flags)
  if gcc?
    expanded_flags = RbConfig.expand(flags.dup)
    debug_option_pattern = /(^|\s)-g(?:gdb)?\d?(\s|$)/
    if debug_option_pattern.match?(expanded_flags)
      expanded_flags.gsub(debug_option_pattern, '\\1-ggdb3\\2')
    else
      flags + " -ggdb3"
    end
  else
    flags
  end
end

checking_for(checking_message("--enable-debug-build option")) do
  enable_debug_build = enable_config("debug-build", false)
  if enable_debug_build
    $CFLAGS = disable_optimization_build_flag($CFLAGS)
    $CFLAGS = enable_debug_build_flag($CFLAGS)
  end
  enable_debug_build
end

libffi_version = nil
have_libffi = false
bundle = with_config("libffi-source-dir")
unless bundle
  dir_config 'libffi'

  if pkg_config("libffi")
    libffi_version = pkg_config("libffi", "modversion")
  end

  have_ffi_header = false
  if have_header(ffi_header = 'ffi.h')
    have_ffi_header = true
  elsif have_header(ffi_header = 'ffi/ffi.h')
    $defs.push('-DUSE_HEADER_HACKS')
    have_ffi_header = true
  end
  if have_ffi_header && (have_library('ffi') || have_library('libffi'))
    have_libffi = true
  end
end

unless have_libffi
  if bundle
    libffi_srcdir = libffi_package_name = bundle
  else
    raise "missing libffi. Please install libffi or use --with-libffi-source-dir with libffi source location."
  end
  ffi_header = 'ffi.h'
  libffi = Struct.new(*%I[dir srcdir builddir include lib a cflags ldflags opt arch]).new
  libffi.dir = libffi_package_name
  if $srcdir == "."
    libffi.builddir = libffi_package_name
    libffi.srcdir = "."
  else
    libffi.builddir = libffi.dir
    libffi.srcdir = relative_from(libffi_srcdir, "..")
  end
  libffi.include = "#{libffi.builddir}/include"
  libffi.lib = "#{libffi.builddir}/.libs"
  libffi.a = "#{libffi.lib}/libffi_convenience.#{$LIBEXT}"
  nowarn = CONFIG.merge("warnflags"=>"")
  libffi.cflags = RbConfig.expand("$(CFLAGS)".dup, nowarn)
  libffi_version = libffi_package_name[/libffi-(.*)/, 1]

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
        Logging.message("%s\n", e.message)
      end
      raise "failed to configure libffi. Please install libffi."
    end
  end
  if $mswin && File.file?("#{libffi.include}/ffitarget.h")
    FileUtils.rm_f("#{libffi.include}/ffitarget.h")
  end
  unless File.file?("#{libffi.include}/ffitarget.h")
    FileUtils.cp("#{libffi_srcdir}/src/x86/ffitarget.h", libffi.include, preserve: true)
  end
  $INCFLAGS << " -I" << libffi.include
end

if libffi_version
  # If libffi_version contains rc version, just ignored.
  libffi_version = libffi_version.gsub(/-rc\d+/, '')
  libffi_version = (libffi_version.split('.').map(&:to_i) + [0,0])[0,3]
  $defs.push(%{-DRUBY_LIBFFI_MODVERSION=#{ '%d%03d%03d' % libffi_version }})
  warn "libffi_version: #{libffi_version.join('.')}"
end

case
when $mswin, $mingw, (libffi_version && (libffi_version <=> [3, 2]) >= 0)
  $defs << "-DUSE_FFI_CLOSURE_ALLOC=1"
when (libffi_version && (libffi_version <=> [3, 2]) < 0)
else
  have_func('ffi_closure_alloc', ffi_header)
end

if libffi_version
  if (libffi_version <=> [3, 0, 11]) >= 0
    $defs << "-DHAVE_FFI_PREP_CIF_VAR"
  end
else
  have_func('ffi_prep_cif_var', ffi_header)
end

have_header 'sys/mman.h'
have_header 'link.h'

if have_header "dlfcn.h"
  have_library "dl"

  %w{ dlopen dlclose dlsym }.each do |func|
    abort "missing function #{func}" unless have_func(func)
  end

  have_func "dlerror"
  have_func "dlinfo"
  have_const("RTLD_DI_LINKMAP", "dlfcn.h")
elsif have_header "windows.h"
  %w{ LoadLibrary FreeLibrary GetProcAddress GetModuleFileName }.each do |func|
    abort "missing function #{func}" unless have_func(func)
  end

  have_library "ws2_32"
end

have_const('FFI_STDCALL', ffi_header)

config = File.read(RbConfig.expand(File.join($arch_hdrdir, "ruby/config.h")))
types = {"SIZE_T"=>"SSIZE_T", "PTRDIFF_T"=>nil, "INTPTR_T"=>nil}
types.each do |type, signed|
  if /^\#define\s+SIZEOF_#{type}\s+(SIZEOF_(.+)|\d+)/ =~ config
    if size = $2 and size != 'VOIDP'
      size = types.fetch(size) {size}
      $defs << "-DTYPE_#{signed||type}=TYPE_#{size}"
    end
    if signed
      check_signedness(type.downcase, "stddef.h")
    end
  else
    check_signedness(type.downcase, "stddef.h")
  end
end

if libffi
  $LOCAL_LIBS.prepend("#{libffi.a} ").strip! # to exts.mk
  $INCFLAGS.gsub!(/-I#{libffi.dir}/, '-I$(LIBFFI_DIR)')
end
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
