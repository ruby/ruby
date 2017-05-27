require File.expand_path('../../../spec_helper', __FILE__)
$extmk = false

require 'rbconfig'

OBJDIR ||= File.expand_path("../../../ext/#{RUBY_NAME}/#{RUBY_VERSION}", __FILE__)
mkdir_p(OBJDIR)

def extension_path
  File.expand_path("../ext", __FILE__)
end

def object_path
  OBJDIR
end

def compile_extension(name)
  preloadenv = RbConfig::CONFIG["PRELOADENV"] || "LD_PRELOAD"
  preload, ENV[preloadenv] = ENV[preloadenv], nil if preloadenv

  path = extension_path
  objdir = object_path

  # TODO use rakelib/ext_helper.rb?
  arch_hdrdir = nil

  if RUBY_NAME == 'rbx'
    hdrdir = RbConfig::CONFIG["rubyhdrdir"]
  elsif RUBY_NAME =~ /^ruby/
    hdrdir = RbConfig::CONFIG["rubyhdrdir"]
    arch_hdrdir = RbConfig::CONFIG["rubyarchhdrdir"]
  elsif RUBY_NAME == 'jruby'
    require 'mkmf'
    hdrdir = $hdrdir
  elsif RUBY_NAME == "maglev"
    require 'mkmf'
    hdrdir = $hdrdir
  elsif RUBY_NAME == 'truffleruby'
    return compile_truffleruby_extconf_make(name, path, objdir)
  else
    raise "Don't know how to build C extensions with #{RUBY_NAME}"
  end

  ext       = "#{name}_spec"
  source    = File.join(path, "#{ext}.c")
  obj       = File.join(objdir, "#{ext}.#{RbConfig::CONFIG['OBJEXT']}")
  lib       = File.join(objdir, "#{ext}.#{RbConfig::CONFIG['DLEXT']}")

  ruby_header     = File.join(hdrdir, "ruby.h")
  rubyspec_header = File.join(path, "rubyspec.h")

  return lib if File.exist?(lib) and File.mtime(lib) > File.mtime(source) and
                File.mtime(lib) > File.mtime(ruby_header) and
                File.mtime(lib) > File.mtime(rubyspec_header) and
                true            # sentinel

  # avoid problems where compilation failed but previous shlib exists
  File.delete lib if File.exist? lib

  cc        = RbConfig::CONFIG["CC"]
  cflags    = (ENV["CFLAGS"] || RbConfig::CONFIG["CFLAGS"]).dup
  cflags   += " #{RbConfig::CONFIG["ARCH_FLAG"]}" if RbConfig::CONFIG["ARCH_FLAG"]
  cflags   += " #{RbConfig::CONFIG["CCDLFLAGS"]}" if RbConfig::CONFIG["CCDLFLAGS"]
  cppflags  = (ENV["CPPFLAGS"] || RbConfig::CONFIG["CPPFLAGS"]).dup
  incflags  = "-I#{path}"
  incflags << " -I#{arch_hdrdir}" if arch_hdrdir
  incflags << " -I#{hdrdir}"
  csrcflag  = RbConfig::CONFIG["CSRCFLAG"]
  coutflag  = RbConfig::CONFIG["COUTFLAG"]

  compile_cmd = "#{cc} #{incflags} #{cflags} #{cppflags} #{coutflag}#{obj} -c #{csrcflag}#{source}"
  output = `#{compile_cmd}`

  unless $?.success? and File.exist?(obj)
    puts "\nERROR:\n#{compile_cmd}\n#{output}"
    puts "incflags=#{incflags}"
    puts "cflags=#{cflags}"
    puts "cppflags=#{cppflags}"
    raise "Unable to compile \"#{source}\""
  end

  ldshared  = RbConfig::CONFIG["LDSHARED"]
  ldshared += " #{RbConfig::CONFIG["ARCH_FLAG"]}" if RbConfig::CONFIG["ARCH_FLAG"]
  libs      = RbConfig::CONFIG["LIBS"]
  dldflags  = "#{RbConfig::CONFIG["LDFLAGS"]} #{RbConfig::CONFIG["DLDFLAGS"]} #{RbConfig::CONFIG["EXTDLDFLAGS"]}"
  dldflags.sub!(/-Wl,-soname,\S+/, '')

  if /mswin/ =~ RUBY_PLATFORM
    dldflags.sub!("$(LIBPATH)", RbConfig::CONFIG["LIBPATHFLAG"] % path)
    libs    += RbConfig::CONFIG["LIBRUBY"]
    outflag  = RbConfig::CONFIG["OUTFLAG"]

    link_cmd = "#{ldshared} #{outflag}#{lib} #{obj} #{libs} -link #{dldflags} /export:Init_#{ext}"
  else
    libpath   = "-L#{path}"
    dldflags.sub!("$(TARGET_ENTRY)", "Init_#{ext}")

    link_cmd = "#{ldshared} #{obj} #{libpath} #{dldflags} #{libs} -o #{lib}"
  end
  output = `#{link_cmd}`

  unless $?.success?
    puts "\nERROR:\n#{link_cmd}\n#{output}"
    raise "Unable to link \"#{source}\""
  end

  lib
ensure
  ENV[preloadenv] = preload if preloadenv
end

def compile_truffleruby_extconf_make(name, path, objdir)
  ext = "#{name}_spec"
  file = "#{ext}.c"
  source = "#{path}/#{ext}.c"
  lib = "#{objdir}/#{ext}.#{RbConfig::CONFIG['DLEXT']}"

  # Copy needed source files to tmpdir
  tmpdir = tmp("cext_#{name}")
  Dir.mkdir tmpdir
  begin
    ["rubyspec.h", "truffleruby.h", "#{ext}.c"].each do |file|
      cp "#{path}/#{file}", "#{tmpdir}/#{file}"
    end

    Dir.chdir(tmpdir) do
      required = require 'mkmf'
      # Reinitialize mkmf if already required
      init_mkmf unless required
      create_makefile(ext, tmpdir)
      system "make"

      copy_exts = RbConfig::CONFIG.values_at('OBJEXT', 'DLEXT')
      Dir.glob("*.{#{copy_exts.join(',')}}") do |file|
        cp file, "#{objdir}/#{file}"
      end
    end
  ensure
    rm_r tmpdir
  end

  lib
end

def load_extension(name)
  require compile_extension(name)
rescue LoadError
  if %r{/usr/sbin/execerror ruby "\(ld 3 1 main ([/a-zA-Z0-9_\-.]+_spec\.so)"} =~ $!.message
    system('/usr/sbin/execerror', "#{RbConfig::CONFIG["bindir"]}/ruby", "(ld 3 1 main #{$1}")
  end
  raise
end

# Constants
CAPI_SIZEOF_LONG = [0].pack('l!').size
