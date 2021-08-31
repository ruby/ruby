# Require the main spec_helper.rb at the end to let `ruby ...spec.rb` work

# MRI magic to use built but not installed ruby
$extmk = false

require 'rbconfig'

OBJDIR ||= File.expand_path("../../../ext/#{RUBY_ENGINE}/#{RUBY_VERSION}", __FILE__)

def object_path
  path = OBJDIR
  if ENV['SPEC_CAPI_CXX'] == 'true'
    path = "#{path}/cxx"
  end
  mkdir_p(path)
  path
end

def compile_extension(name)
  debug = false
  cxx = ENV['SPEC_CAPI_CXX'] == 'true'
  run_mkmf_in_process = RUBY_ENGINE == 'truffleruby'

  core_ext_dir = File.expand_path("../ext", __FILE__)

  spec_caller_location = caller_locations.find { |c| c.path.end_with?('_spec.rb') }
  spec_file_path = spec_caller_location.path
  spec_ext_dir = File.expand_path("../ext", spec_file_path)

  ext = "#{name}_spec"
  lib = "#{object_path}/#{ext}.#{RbConfig::CONFIG['DLEXT']}"
  ruby_header = "#{RbConfig::CONFIG['rubyhdrdir']}/ruby.h"

  if RbConfig::CONFIG["ENABLE_SHARED"] == "yes"
    libdirname = RbConfig::CONFIG['libdirname'] # defined since 2.1
    libruby = "#{RbConfig::CONFIG[libdirname]}/#{RbConfig::CONFIG['LIBRUBY']}"
  end

  begin
    mtime = File.mtime(lib)
  rescue Errno::ENOENT
    # not found, then compile
  else
    case # if lib is older than headers, source or libruby, then recompile
    when mtime <= File.mtime("#{core_ext_dir}/rubyspec.h")
    when mtime <= File.mtime("#{spec_ext_dir}/#{ext}.c")
    when mtime <= File.mtime(ruby_header)
    when libruby && mtime <= File.mtime(libruby)
    else
      return lib # up-to-date
    end
  end

  # Copy needed source files to tmpdir
  tmpdir = tmp("cext_#{name}")
  Dir.mkdir(tmpdir)
  begin
    ["#{core_ext_dir}/rubyspec.h", "#{spec_ext_dir}/#{ext}.c"].each do |file|
      if cxx and file.end_with?('.c')
        cp file, "#{tmpdir}/#{File.basename(file, '.c')}.cpp"
      else
        cp file, "#{tmpdir}/#{File.basename(file)}"
      end
    end

    Dir.chdir(tmpdir) do
      if run_mkmf_in_process
        required = require 'mkmf'
        # Reinitialize mkmf if already required
        init_mkmf unless required
        create_makefile(ext, tmpdir)
      else
        File.write("extconf.rb", <<-RUBY)
          require 'mkmf'
          $ruby = ENV.values_at('RUBY_EXE', 'RUBY_FLAGS').join(' ')
          # MRI magic to consider building non-bundled extensions
          $extout = nil
          append_cflags '-Wno-declaration-after-statement'
          create_makefile(#{ext.inspect})
        RUBY
        output = ruby_exe("extconf.rb")
        raise "extconf failed:\n#{output}" unless $?.success?
        $stderr.puts output if debug
      end

      # Do not capture stderr as we want to show compiler warnings
      make, opts = setup_make
      output = IO.popen([make, "V=1", "DESTDIR=", opts], &:read)
      raise "#{make} failed:\n#{output}" unless $?.success?
      $stderr.puts output if debug

      cp File.basename(lib), lib
    end
  ensure
    rm_r tmpdir
  end

  File.chmod(0755, lib)
  lib
end

def setup_make
  make = ENV['MAKE']
  make ||= (RbConfig::CONFIG['host_os'].include?("mswin") ? "nmake" : "make")
  make_flags = ENV["MAKEFLAGS"] || ''

  # suppress logo of nmake.exe to stderr
  if File.basename(make, ".*").downcase == "nmake" and !make_flags.include?("l")
    ENV["MAKEFLAGS"] = "l#{make_flags}"
  end

  opts = {}
  if /(?:\A|\s)--jobserver-(?:auth|fds)=(\d+),(\d+)/ =~ make_flags
    begin
      r = IO.for_fd($1.to_i(10), "rb", autoclose: false)
      w = IO.for_fd($2.to_i(10), "wb", autoclose: false)
    rescue Errno::EBADF
    else
      opts[r] = r
      opts[w] = w
    end
  end

  [make, opts]
end

def load_extension(name)
  ext_path = compile_extension(name)
  require ext_path
  ext_path
rescue LoadError => e
  if %r{/usr/sbin/execerror ruby "\(ld 3 1 main ([/a-zA-Z0-9_\-.]+_spec\.so)"} =~ e.message
    system('/usr/sbin/execerror', "#{RbConfig::CONFIG["bindir"]}/ruby", "(ld 3 1 main #{$1}")
  end
  raise
end

# Constants
CAPI_SIZEOF_LONG = [0].pack('l!').size

# Require the main spec_helper.rb only here so load_extension() is defined
# when running specs with `ruby ...spec.rb`
require_relative '../../spec_helper'
